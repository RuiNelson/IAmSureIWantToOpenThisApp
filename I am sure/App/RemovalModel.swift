import Foundation
import Observation

/// Shared state for the main window: runs removals and drives navigation.
@Observable final class RemovalModel {
    var path: [RemoveQuarantineResult] = []
    private(set) var isWorking = false

    /// Removes quarantine from the given file URLs and shows the result.
    /// Returns `false` when there's nothing to process or a removal is already running.
    @discardableResult
    func process(_ urls: [URL]) -> Bool {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty, !isWorking else { return false }

        isWorking = true
        Task {
            let result = await Quarantine.remove(from: fileURLs)
            isWorking = false
            path = [result]
        }
        return true
    }
}
