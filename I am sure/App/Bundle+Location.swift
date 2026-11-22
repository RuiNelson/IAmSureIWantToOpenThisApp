import Foundation

extension Bundle {
    /// Where an app is running from, which says whether it's "installed".
    nonisolated enum Location: Hashable, Sendable {
        /// `/Applications` or `~/Applications` (including subfolders such as `Utilities`).
        case applications
        /// `~/Downloads`.
        case downloads
        /// Anything under `/Volumes`: disk images, network shares, external drives...
        case volume
        /// Anywhere else (the Desktop, a development build folder...).
        case other

        /// Whether an app running from here is likely to go away (eject, clean-up of Downloads)
        /// and so is worth offering to keep.
        var isTransient: Bool { self == .downloads || self == .volume }

        /// Both folders an app may be installed in, `/Applications` first.
        static var applicationFolders: [URL] {
            [FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask),
             FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask)].flatMap { $0 }
        }

        static var downloadsFolder: URL? {
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        }

        /// Classifies `url`. Symlinks are resolved on both sides first, so `/Volumes/Macintosh HD`
        /// (a symlink to `/`) is the startup disk, not a mounted volume.
        init(
            of url: URL,
            applicationFolders: [URL] = Self.applicationFolders,
            downloadsFolder: URL? = Self.downloadsFolder
        ) {
            let components = url.resolvingSymlinksInPath().pathComponents
            func isInside(_ folder: URL) -> Bool {
                let folderComponents = folder.resolvingSymlinksInPath().pathComponents
                return components.count > folderComponents.count && components.starts(with: folderComponents)
            }

            if applicationFolders.contains(where: isInside) {
                self = .applications
            } else if let downloadsFolder, isInside(downloadsFolder) {
                self = .downloads
            } else if components.count > 2, components[1] == "Volumes" {
                self = .volume
            } else {
                self = .other
            }
        }
    }

    /// Where this bundle is running from. See `originalURL`.
    nonisolated var location: Location { Location(of: originalURL) }

    /// The bundle's real location. macOS runs a quarantined app that was never moved by the user
    /// from a randomized read-only mount (App Translocation); this gives back the path it was
    /// opened from. Equal to `bundleURL` for anything else.
    nonisolated var originalURL: URL {
        guard bundleURL.path.contains("/AppTranslocation/") else { return bundleURL }
        return Self.untranslocated(bundleURL) ?? bundleURL
    }

    /// `SecTranslocateCreateOriginalPathForURL` is a private Security function, so it's looked up
    /// at run time and everything falls back to the translocated URL if it's missing.
    private nonisolated static func untranslocated(_ url: URL) -> URL? {
        typealias CreateOriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        let createOriginalPath = unsafeBitCast(symbol, to: CreateOriginalPath.self)
        return createOriginalPath(url as CFURL, nil)?.takeRetainedValue() as URL?
    }
}
