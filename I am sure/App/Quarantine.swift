import Foundation
import Darwin

/// Outcome of removing `com.apple.quarantine` from a batch of dropped items.
nonisolated struct RemoveQuarantineResult: Hashable, Sendable {
    let id = UUID()
    let items: [ItemResult]
}

/// Outcome for a single dropped file, folder or app bundle.
nonisolated struct ItemResult: Hashable, Sendable, Identifiable {
    struct Failure: Hashable, Sendable {
        /// Path relative to the dropped item ("" for the item itself).
        let relativePath: String
        let message: String
    }

    enum Status: Hashable, Sendable {
        case removed
        case notQuarantined
        case failed
    }

    var id: URL { url }
    let url: URL
    /// Number of files (the item itself plus anything inside it) that had the attribute removed.
    let clearedCount: Int
    let failures: [Failure]

    var status: Status {
        if !failures.isEmpty { return .failed }
        return clearedCount > 0 ? .removed : .notQuarantined
    }
}

nonisolated enum Quarantine {
    static let attributeName = "com.apple.quarantine"

    /// Removes the quarantine attribute from every URL, recursing into folders and bundles.
    /// Runs off the main actor: large app bundles can contain thousands of files.
    @concurrent
    static func remove(from urls: [URL]) async -> RemoveQuarantineResult {
        RemoveQuarantineResult(items: urls.map(removeRecursively))
    }

    static func isQuarantined(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, attributeName, nil, 0, 0, XATTR_NOFOLLOW) >= 0
        }
    }

    private static func removeRecursively(_ root: URL) -> ItemResult {
        var cleared = 0
        var failures: [ItemResult.Failure] = []

        func relativePath(of url: URL) -> String {
            let rootPath = root.standardizedFileURL.path
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootPath) else { return path }
            return String(path.dropFirst(rootPath.count).drop(while: { $0 == "/" }))
        }

        func handle(_ url: URL) {
            switch removeAttribute(at: url) {
            case .removed: cleared += 1
            case .absent: break
            case .failed(let message):
                failures.append(.init(relativePath: relativePath(of: url), message: message))
            }
        }

        handle(root)

        let isDirectory = (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDirectory {
            // Includes hidden files and package contents; symlinked directories aren't followed.
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [],
                errorHandler: { url, error in
                    failures.append(.init(relativePath: relativePath(of: url), message: error.localizedDescription))
                    return true
                }
            )
            while let url = enumerator?.nextObject() as? URL {
                handle(url)
            }
        }

        return ItemResult(url: root, clearedCount: cleared, failures: failures)
    }

    private enum AttributeRemoval {
        case removed, absent, failed(String)
    }

    private static func removeAttribute(at url: URL) -> AttributeRemoval {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return .failed("Invalid path") }
            if removexattr(path, attributeName, XATTR_NOFOLLOW) == 0 { return .removed }
            let code = errno
            if code == ENOATTR { return .absent }
            return .failed(String(cString: strerror(code)))
        }
    }
}
