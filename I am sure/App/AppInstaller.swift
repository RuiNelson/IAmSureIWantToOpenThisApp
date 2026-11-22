import Foundation

/// Copies the running app into an Applications folder.
nonisolated enum AppInstaller {
    /// `/Applications` if the user can write to it (standard users can't), else `~/Applications`,
    /// which is created if needed.
    static func destinationFolder(fileManager: FileManager = .default) throws -> URL {
        let system = fileManager.urls(for: .applicationDirectory, in: .localDomainMask)[0]
        if fileManager.isWritableFile(atPath: system.path) { return system }

        let user = fileManager.urls(for: .applicationDirectory, in: .userDomainMask)[0]
        try fileManager.createDirectory(at: user, withIntermediateDirectories: true)
        return user
    }

    /// Copies `source` into the destination folder and returns the copy's URL. Only copies: the
    /// source is left alone and quarantine isn't touched. An app already there with the same name
    /// (typically an older version) is moved to the Trash first.
    @concurrent
    static func copy(_ source: URL) async throws -> URL {
        let fileManager = FileManager.default
        let destination = try destinationFolder(fileManager: fileManager).appending(path: source.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }
}
