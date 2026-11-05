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
    /// `UserDefaults` key set once the user has acknowledged the risks.
    static let acknowledgedRisksKey = "ackRisks"

    var path: [Route] = []
    private(set) var isWorking = false
    /// Items handed to the app from outside (the Finder action extension, the Dock icon) that
    /// are waiting for the risks to be acknowledged or for the current run to finish.
    private(set) var pendingURLs: [URL] = []

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
            processPending()
        }
        return true
    }

    /// Entry point for items opened from outside the window (e.g. the "Let me open this App"
    /// Finder action). Runs right away when possible; otherwise queues them until the risks are
    /// acknowledged or the current run finishes.
    func open(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }
        pendingURLs.append(contentsOf: fileURLs.filter { !pendingURLs.contains($0) })
        processPending()
    }

    /// Processes queued items, if the risks have been acknowledged and nothing is running.
    func processPending() {
        guard !pendingURLs.isEmpty, !isWorking,
              UserDefaults.standard.bool(forKey: Self.acknowledgedRisksKey) else { return }
        let urls = pendingURLs
        pendingURLs = []
        process(urls)
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
            processPending()
        }
    }
}
