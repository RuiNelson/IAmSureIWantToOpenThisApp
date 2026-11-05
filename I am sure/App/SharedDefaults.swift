import Foundation

nonisolated extension UserDefaults {
    /// App Group shared with the "Let me open this App" Finder action (see the entitlements).
    static let appGroup = "98DYJ8BJ46.com.ruinelson.iamsure"

    /// Key set once the user has acknowledged the risks.
    static let acknowledgedRisksKey = "ackRisks"

    /// Defaults the Finder action can read too: it skips its warning once the risks are acknowledged.
    static let shared: UserDefaults = {
        guard let group = UserDefaults(suiteName: appGroup) else { return .standard }
        // Earlier versions stored the acknowledgement in the app's own defaults.
        if UserDefaults.standard.bool(forKey: acknowledgedRisksKey), !group.bool(forKey: acknowledgedRisksKey) {
            group.set(true, forKey: acknowledgedRisksKey)
        }
        return group
    }()
}
