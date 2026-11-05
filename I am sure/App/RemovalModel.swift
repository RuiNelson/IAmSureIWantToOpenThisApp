import Foundation
import Observation
import OSLog

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
    /// Whether the "Select Files…" panel is showing (driven by the File menu and the drop screen's button).
    var isImporting = false
    /// Items handed to the app from outside (the Finder action extension, the Dock icon) that
    /// are waiting for the risks to be acknowledged or for the current run to finish.
    private(set) var pendingURLs: [URL] = []
    private var openGeneration = 0
    /// When the last batch of items opened from outside finished; see `processPending()`.
    private var lastExternalBatch: Date?

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
        run(urls, keeping: [], isExternal: false)
    }

    /// Removes quarantine from `urls` and shows their results after `previous` (minus any item
    /// processed again).
    @discardableResult
    private func run(_ urls: [URL], keeping previous: [ItemResult], isExternal: Bool) -> Bool {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty, !isWorking else { return false }

        isWorking = true
        Task {
            let removed = await Quarantine.remove(from: fileURLs)
            isWorking = false
            let result = RemoveQuarantineResult(
                items: previous.filter { !fileURLs.contains($0.url) } + removed.items
            )
            var route: [Route] = [.result(result)]
            let failed = result.items.filter { $0.status == .failed }.map(\.url)
            if !failed.isEmpty { route.append(.copy(CopyRequest(urls: failed))) }
            path = route
            Logger(subsystem: "com.ruinelson.iamsure", category: "Removal")
                .notice("Showing result for \(result.items.count) item(s), \(failed.count) failed")
            lastExternalBatch = isExternal ? .now : nil
            processPending()
        }
        return true
    }

    /// Entry point for items opened from outside the window (e.g. the "Let me open this App"
    /// Finder action). Queues them until the risks are acknowledged or the current run finishes.
    /// The Finder action sends one item per request, so items arriving within a moment of each
    /// other are processed as one batch.
    func open(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }
        pendingURLs.append(contentsOf: fileURLs.filter { !pendingURLs.contains($0) })

        openGeneration += 1
        let generation = openGeneration
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard generation == openGeneration else { return } // more items arrived meanwhile
            processPending()
        }
    }

    /// Processes queued items, if the risks have been acknowledged and nothing is running.
    /// Items that trail the previous external batch by a few seconds (Launch Services checks
    /// quarantined apps before handing them over) join its result instead of replacing it.
    func processPending() {
        guard !pendingURLs.isEmpty, !isWorking,
              UserDefaults.shared.bool(forKey: UserDefaults.acknowledgedRisksKey) else { return }
        let urls = pendingURLs
        pendingURLs = []
        let joinsPrevious = lastExternalBatch.map { Date.now.timeIntervalSince($0) < 10 } ?? false
        run(urls, keeping: joinsPrevious ? currentResult?.items ?? [] : [], isExternal: true)
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
            lastExternalBatch = nil
            processPending()
        }
    }
}
