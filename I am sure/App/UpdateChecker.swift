import Foundation

/// A published GitHub release.
nonisolated struct Release: Hashable, Sendable, Decodable {
    let tagName: String
    /// The release's page on GitHub.
    let htmlURL: URL

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    /// The tag without its `v` prefix ("v1.2.0" is version "1.2.0").
    var version: String {
        tagName.hasPrefix("v") || tagName.hasPrefix("V") ? String(tagName.dropFirst()) : tagName
    }

    /// Whether this release is newer than `current`, comparing dot-separated numbers
    /// ("1.10" is newer than "1.9", and "1.1.0" equals "1.1").
    func isNewer(than current: String) -> Bool {
        func numbers(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        var latest = numbers(version)
        var running = numbers(current)
        let count = max(latest.count, running.count)
        latest += Array(repeating: 0, count: count - latest.count)
        running += Array(repeating: 0, count: count - running.count)
        return running.lexicographicallyPrecedes(latest)
    }
}

nonisolated enum UpdateChecker {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/RuiNelson/IAmSureIWantToOpenThisApp/releases/latest")!

    /// The app is never checked more often than this.
    static let minimumInterval: TimeInterval = 24 * 60 * 60

    /// Whether enough time has passed since `lastCheck` (or there was none).
    static func isDue(lastCheck: Date?, now: Date = .now) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= minimumInterval
    }

    /// The latest published (non-draft, non-prerelease) release.
    @concurrent
    static func latestRelease() async throws -> Release {
        var request = URLRequest(url: latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Release.self, from: data)
    }
}

extension Bundle {
    /// The running app's version (`CFBundleShortVersionString`).
    nonisolated var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}
