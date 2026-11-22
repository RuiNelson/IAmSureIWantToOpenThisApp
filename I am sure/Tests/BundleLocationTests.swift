import Foundation
import Testing
@testable import I_am_sure_I_want_to_open_this_App

@Suite struct BundleLocationTests {
    private let applications = [URL(filePath: "/Applications"), URL(filePath: "/Users/someone/Applications")]
    private let downloads = URL(filePath: "/Users/someone/Downloads")

    private func location(of path: String) -> Bundle.Location {
        Bundle.Location(of: URL(filePath: path), applicationFolders: applications, downloadsFolder: downloads)
    }

    @Test func applicationsFolders() {
        #expect(location(of: "/Applications/Foo.app") == .applications)
        #expect(location(of: "/Applications/Utilities/Foo.app") == .applications)
        #expect(location(of: "/Users/someone/Applications/Foo.app") == .applications)
    }

    @Test func downloadsFolder() {
        #expect(location(of: "/Users/someone/Downloads/Foo.app") == .downloads)
        #expect(location(of: "/Users/someone/Downloads/Folder/Foo.app") == .downloads)
    }

    @Test func volumes() {
        #expect(location(of: "/Volumes/Foo Installer/Foo.app") == .volume)
        #expect(location(of: "/Volumes/Share/Apps/Foo.app") == .volume)
    }

    @Test func otherPlaces() {
        #expect(location(of: "/Users/someone/Desktop/Foo.app") == .other)
        #expect(location(of: "/Users/someone/Downloads-old/Foo.app") == .other)
        #expect(location(of: "/Volumes") == .other)
    }

    @Test func foldersThemselvesAreNotInside() {
        #expect(location(of: "/Applications") == .other)
        #expect(location(of: "/Users/someone/Downloads") == .other)
    }

    @Test func onlyDownloadsAndVolumesAreTransient() {
        #expect(Bundle.Location.downloads.isTransient)
        #expect(Bundle.Location.volume.isTransient)
        #expect(!Bundle.Location.applications.isTransient)
        #expect(!Bundle.Location.other.isTransient)
    }

    /// `/Volumes/<startup disk>` is a symlink to `/`, not a mounted volume.
    @Test func startupDiskSymlinkIsNotAVolume() throws {
        let startupDisk = try #require(
            try FileManager.default.contentsOfDirectory(atPath: "/Volumes")
                .first { (try? FileManager.default.destinationOfSymbolicLink(atPath: "/Volumes/\($0)")) == "/" }
        )
        // Symlinks only resolve for paths that exist, so these are real folders.
        #expect(location(of: "/Volumes/\(startupDisk)/Applications/Utilities") == .applications)
        #expect(location(of: "/Volumes/\(startupDisk)/Users") == .other)
    }
}
