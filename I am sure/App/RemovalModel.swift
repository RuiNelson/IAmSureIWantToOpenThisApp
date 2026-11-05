import Foundation
import Observation

/// Screens pushed on the main navigation stack.
enum Route: Hashable {
    case result(RemoveQuarantineResult)
    case copy(CopyRequest)
}

/// Items that couldn't be modified in place and may be copied somewhere writable instead.
struct CopyRequest: Hashable {
    let id = UUID()
    let urls: [URL]
}

/// Shared state for the main window: runs removals and drives navigation.
@Observable final class RemovalModel {
    var path: [Route] = []
    private(set) var isWorking = false

    private var currentResult: RemoveQuarantineResult? {
        path.reversed().lazy.compactMap { route in
            if case .result(let result) = route { result } else { nil }
        }.first
    }

    /// Removes quarantine from the given file URLs and shows the result.
    /// If anything fails (e.g. a read-only disk image), the copy options are shown right after.
    /// Returns `false` when there's nothing to process or a removal is already running.
    @discardableResult
    func process(_ urls: [URL]) -> Bool {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty, !isWorking else { return false }

        isWorking = true
        Task {
            let result = await Quarantine.remove(from: fileURLs)
            isWorking = false
            var route: [Route] = [.result(result)]
            let failed = result.items.filter { $0.status == .failed }.map(\.url)
            if !failed.isEmpty { route.append(.copy(CopyRequest(urls: failed))) }
            path = route
        }
        return true
    }

    /// Copies the given (failed) items into `directory`, removes quarantine from the copies, and
    /// replaces those items in the current result. Items that already succeeded are kept as-is.
    func copyAndProcess(_ urls: [URL], to directory: URL) {
        guard !urls.isEmpty, !isWorking else { return }

        let previous = currentResult?.items ?? []
        isWorking = true
        Task {
            let copied = await Quarantine.copyAndRemove(from: urls, to: directory)
            isWorking = false
            let kept = previous.filter { !urls.contains($0.url) }
            path = [.result(RemoveQuarantineResult(items: kept + copied))]
        }
    }
}
