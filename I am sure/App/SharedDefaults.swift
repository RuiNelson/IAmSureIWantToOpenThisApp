import Foundation

nonisolated extension UserDefaults {
    /// App Group of the app (see the entitlements); earlier versions shared it with the Finder action.
    static let appGroup = "98DYJ8BJ46.com.ruinelson.iamsure"

    /// Key set once the user has acknowledged the risks.
    static let acknowledgedRisksKey = "ackRisks"

    /// The app's defaults in its App Group.
    static let shared: UserDefaults = {
        guard let group = UserDefaults(suiteName: appGroup) else { return .standard }
        // Earlier versions stored the acknowledgement in the app's own defaults.
        if UserDefaults.standard.bool(forKey: acknowledgedRisksKey), !group.bool(forKey: acknowledgedRisksKey) {
            group.set(true, forKey: acknowledgedRisksKey)
        }
        return group
    }()
}
