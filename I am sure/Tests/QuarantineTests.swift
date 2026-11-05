import Darwin
import Foundation
import Testing
@testable import I_am_sure_I_want_to_open_this_App

/// Exercises the real file system (and extended attributes) inside a throwaway directory.
@Suite struct QuarantineTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "QuarantineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: Helpers

    private func makeFile(_ name: String, in directory: URL? = nil, quarantined: Bool = true) throws -> URL {
        let url = (directory ?? root).appending(path: name)
        try Data("x".utf8).write(to: url)
        if quarantined { try quarantine(url) }
        return url
    }

    private func makeDirectory(_ name: String, in directory: URL? = nil) throws -> URL {
        let url = (directory ?? root).appending(path: name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func quarantine(_ url: URL) throws {
        let value = "0083;00000000;Test;"
        let status = url.withUnsafeFileSystemRepresentation { path in
            setxattr(path, Quarantine.attributeName, value, value.utf8.count, 0, XATTR_NOFOLLOW)
        }
        try #require(status == 0)
    }

    private func cleanUp() { try? FileManager.default.removeItem(at: root) }

    // MARK: Remove

    @Test func removesFromSingleFile() async throws {
        defer { cleanUp() }
        let file = try makeFile("a.txt")

        let result = await Quarantine.remove(from: [file])

        #expect(result.items.count == 1)
        #expect(result.items[0].status == .removed)
        #expect(result.items[0].clearedCount == 1)
        #expect(!Quarantine.isQuarantined(file))
    }

    @Test func reportsNotQuarantinedWhenAttributeIsAbsent() async throws {
        defer { cleanUp() }
        let file = try makeFile("a.txt", quarantined: false)

        let result = await Quarantine.remove(from: [file])

        #expect(result.items[0].status == .notQuarantined)
        #expect(result.items[0].clearedCount == 0)
    }

    @Test func recursesIntoFoldersIncludingHiddenFiles() async throws {
        defer { cleanUp() }
        let folder = try makeDirectory("Folder")
        let nested = try makeDirectory("Nested", in: folder)
        let files = [
            try makeFile("one.txt", in: folder),
            try makeFile(".hidden", in: nested),
        ]
        try quarantine(folder)

        let result = await Quarantine.remove(from: [folder])

        #expect(result.items[0].status == .removed)
        #expect(result.items[0].clearedCount == 3) // folder + two files
        #expect(!Quarantine.isQuarantined(folder))
        for file in files { #expect(!Quarantine.isQuarantined(file)) }
    }

    @Test func doesNotFollowSymlinkedDirectories() async throws {
        defer { cleanUp() }
        let outside = try makeDirectory("Outside")
        let outsideFile = try makeFile("keep.txt", in: outside)
        let folder = try makeDirectory("Folder")
        try FileManager.default.createSymbolicLink(
            at: folder.appending(path: "link"), withDestinationURL: outside
        )

        _ = await Quarantine.remove(from: [folder])

        #expect(Quarantine.isQuarantined(outsideFile))
    }

    @Test func handlesSeveralItemsIndependently() async throws {
        defer { cleanUp() }
        let quarantined = try makeFile("q.txt")
        let clean = try makeFile("c.txt", quarantined: false)

        let result = await Quarantine.remove(from: [quarantined, clean])

        #expect(result.items.map(\.status) == [.removed, .notQuarantined])
    }

    @Test func reportsFailureForMissingItem() async {
        defer { cleanUp() }
        let missing = root.appending(path: "missing.txt")

        let result = await Quarantine.remove(from: [missing])

        #expect(result.items[0].status == .failed)
        #expect(result.items[0].failures.first?.relativePath == "")
    }

    @Test func reportsFailureForReadOnlyFile() async throws {
        defer {
            // Restore permissions so the cleanup can delete it.
            chmod(root.appending(path: "ro.txt").path, 0o644)
            cleanUp()
        }
        let file = try makeFile("ro.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path)

        let result = await Quarantine.remove(from: [file])

        // Owner-read-only files can still have xattrs removed on some systems; only a
        // failure must be reported consistently with the attribute still being present.
        let item = result.items[0]
        #expect((item.status == .failed) == Quarantine.isQuarantined(file))
    }

    // MARK: Status

    @Test func statusIsDerivedFromCountsAndFailures() {
        let url = URL(filePath: "/tmp/x")
        #expect(ItemResult(url: url, clearedCount: 2, failures: []).status == .removed)
        #expect(ItemResult(url: url, clearedCount: 0, failures: []).status == .notQuarantined)
        let failure = ItemResult.Failure(relativePath: "a", message: "nope")
        #expect(ItemResult(url: url, clearedCount: 5, failures: [failure]).status == .failed)
    }

    // MARK: Copy

    @Test func copyAndRemoveClearsTheCopyAndKeepsTheOriginal() async throws {
        defer { cleanUp() }
        let source = try makeDirectory("Source")
        let file = try makeFile("a.txt", in: source)
        let destination = try makeDirectory("Destination")

        let results = await Quarantine.copyAndRemove(from: [file], to: destination)

        let copy = destination.appending(path: "a.txt")
        #expect(results[0].status == .removed)
        #expect(results[0].url == copy)
        #expect(FileManager.default.fileExists(atPath: copy.path))
        #expect(!Quarantine.isQuarantined(copy))
        #expect(Quarantine.isQuarantined(file))
    }

    @Test func copyAndRemoveNeverOverwritesAndAddsNumericSuffix() async throws {
        defer { cleanUp() }
        let source = try makeDirectory("Source")
        let file = try makeFile("a.txt", in: source)
        let destination = try makeDirectory("Destination")
        _ = try makeFile("a.txt", in: destination, quarantined: false)
        _ = try makeFile("a 2.txt", in: destination, quarantined: false)

        let results = await Quarantine.copyAndRemove(from: [file], to: destination)

        #expect(results[0].url.lastPathComponent == "a 3.txt")
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "a.txt").path))
    }

    @Test func copyAndRemoveSuffixesExtensionlessNames() async throws {
        defer { cleanUp() }
        let source = try makeDirectory("Source")
        let file = try makeFile("README", in: source)
        let destination = try makeDirectory("Destination")
        _ = try makeFile("README", in: destination, quarantined: false)

        let results = await Quarantine.copyAndRemove(from: [file], to: destination)

        #expect(results[0].url.lastPathComponent == "README 2")
    }

    @Test func copyAndRemoveReportsCopyFailureAgainstTheOriginal() async throws {
        defer { cleanUp() }
        let missing = root.appending(path: "missing.txt")
        let destination = try makeDirectory("Destination")

        let results = await Quarantine.copyAndRemove(from: [missing], to: destination)

        #expect(results[0].url == missing)
        #expect(results[0].status == .failed)
        #expect(results[0].failures.first?.message.hasPrefix("Copy failed") == true)
    }
}
