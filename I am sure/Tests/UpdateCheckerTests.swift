import Foundation
import Testing
@testable import I_am_sure_I_want_to_open_this_App

@Suite struct UpdateCheckerTests {
    private func release(_ tag: String) -> Release {
        Release(tagName: tag, htmlURL: URL(string: "https://github.com/x/y/releases/tag/\(tag)")!)
    }

    @Test func decodesGitHubReleaseJSON() throws {
        let json = #"{"id": 1, "tag_name": "v1.2.0", "html_url": "https://github.com/x/y/releases/tag/v1.2.0", "draft": false}"#
        let decoded = try JSONDecoder().decode(Release.self, from: Data(json.utf8))

        #expect(decoded.tagName == "v1.2.0")
        #expect(decoded.version == "1.2.0")
        #expect(decoded.htmlURL.absoluteString == "https://github.com/x/y/releases/tag/v1.2.0")
    }

    @Test func versionDropsThePrefix() {
        #expect(release("v1.1.2").version == "1.1.2")
        #expect(release("1.1.2").version == "1.1.2")
    }

    @Test func comparesVersionsNumerically() {
        #expect(release("v1.1.3").isNewer(than: "1.1.2"))
        #expect(release("v1.2.0").isNewer(than: "1.1.9"))
        #expect(release("v2.0.0").isNewer(than: "1.9.9"))
        #expect(release("v1.10.0").isNewer(than: "1.9.0"))
        #expect(release("v1.1.0.1").isNewer(than: "1.1"))
    }

    @Test func sameOrOlderVersionsAreNotNewer() {
        #expect(!release("v1.1.2").isNewer(than: "1.1.2"))
        #expect(!release("v1.1.0").isNewer(than: "1.1"))
        #expect(!release("v1.1").isNewer(than: "1.1.0"))
        #expect(!release("v1.1.1").isNewer(than: "1.1.2"))
        #expect(!release("v1.9.0").isNewer(than: "1.10.0"))
    }

    @Test func checksAtMostOnceEvery24Hours() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(UpdateChecker.isDue(lastCheck: nil, now: now))
        #expect(!UpdateChecker.isDue(lastCheck: now, now: now))
        #expect(!UpdateChecker.isDue(lastCheck: now.addingTimeInterval(-23 * 3600), now: now))
        #expect(UpdateChecker.isDue(lastCheck: now.addingTimeInterval(-24 * 3600), now: now))
        #expect(UpdateChecker.isDue(lastCheck: now.addingTimeInterval(-3 * 24 * 3600), now: now))
    }
}
