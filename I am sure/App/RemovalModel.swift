import AppKit
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
    /// Whether the "Select Files..." panel is showing (driven by the File menu and the drop screen's button).
    var isImporting = false
    /// Items handed to the app from outside (the Finder action extension, the Dock icon) that
    /// are waiting for the risks to be acknowledged or for the current run to finish.
    private(set) var pendingURLs: [URL] = []
    /// From the moment items arrive from outside until their result is shown. The drop zone is
    /// hidden meanwhile so it doesn't flash before the result. When the app is launched to open
    /// items, the window appears just before they arrive, so it starts out set; see `init(launching:)`.
    private(set) var isReceiving: Bool
    /// Whether the "Do you want to keep this App?" alert is showing.
    var offersKeeping = false
    /// Why copying the app into Applications failed, while the error alert is showing.
    var keepFailure: String?
    /// Whether the app is being copied into Applications (a run in progress, for the progress label).
    private(set) var isKeeping = false
    /// Whether the "check for new versions periodically?" question is showing.
    var asksUpdateCheck = false
    /// A newer release than the running app, while the update alert is showing.
    var availableRelease: Release?
    /// Whether the "You're up to date" alert is showing (after a manual check).
    var isUpToDate = false
    /// Why a manual update check failed, while the error alert is showing.
    var updateFailure: String?
    /// Whether the latest release is being looked up.
    private(set) var isCheckingForUpdates = false
    /// The offer is made once per launch.
    private var hasOfferedKeeping = false
    private var openGeneration = 0
    /// When the last batch of items opened from outside finished; see `processPending()`.
    private var lastExternalBatch: Date?

    /// - Parameter launching: Whether the app is still launching; call `finishLaunching()` once it's done.
    init(launching: Bool = false) {
        isReceiving = launching
    }

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
            if isExternal { isReceiving = false }
            offerKeepingIfNeeded(after: result)
            updateIfNeeded(after: result)
            processPending()
        }
        return true
    }

    /// After quarantine was removed from something, offers to copy this app into Applications
    /// if it's running from a place it may not stay (Downloads, a disk image, a network share...).
    private func offerKeepingIfNeeded(after result: RemoveQuarantineResult) {
        guard !hasOfferedKeeping,
              result.items.contains(where: { $0.status == .removed }),
              Bundle.main.location.isTransient else { return }
        hasOfferedKeeping = true
        offersKeeping = true
    }

    /// When the app is installed in an Applications folder: asks once whether to check for new
    /// versions periodically (after something was actually removed), and if the user said yes,
    /// looks up the latest release, at most once every 24 hours.
    private func updateIfNeeded(after result: RemoveQuarantineResult) {
        guard Bundle.main.location == .applications else { return }
        let defaults = UserDefaults.shared

        switch defaults.object(forKey: UserDefaults.checksForUpdatesKey) as? Bool {
        case nil:
            if result.items.contains(where: { $0.status == .removed }) { asksUpdateCheck = true }
        case true:
            guard UpdateChecker.isDue(lastCheck: defaults.object(forKey: UserDefaults.lastUpdateCheckKey) as? Date) else { return }
            lookUpLatestRelease(manually: false)
        case false:
            break
        }
    }

    /// The "Check for Updates..." menu item: looks up the latest release right away, whatever the
    /// 24-hour limit or the periodic setting, and always reports the outcome.
    func checkForUpdates() {
        lookUpLatestRelease(manually: true)
    }

    /// Looks up the latest release and shows the update alert if it's newer than the running app.
    /// A manual check also reports being up to date and failures; periodic ones stay quiet.
    private func lookUpLatestRelease(manually: Bool) {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        UserDefaults.shared.set(Date.now, forKey: UserDefaults.lastUpdateCheckKey)
        Task {
            defer { isCheckingForUpdates = false }
            do {
                let release = try await UpdateChecker.latestRelease()
                if release.isNewer(than: Bundle.main.shortVersion) {
                    availableRelease = release
                } else if manually {
                    isUpToDate = true
                }
            } catch {
                Logger(subsystem: "com.ruinelson.iamsure", category: "Update")
                    .error("Couldn't check for updates: \(error.localizedDescription, privacy: .public)")
                if manually { updateFailure = error.localizedDescription }
            }
        }
    }

    /// Stores the answer to the "check for new versions periodically?" question.
    func setChecksForUpdates(_ enabled: Bool) {
        UserDefaults.shared.set(enabled, forKey: UserDefaults.checksForUpdatesKey)
    }

    /// Opens the release's page on GitHub in the default browser.
    func openReleasePage(_ release: Release) {
        NSWorkspace.shared.open(release.htmlURL)
    }

    /// Copies this app into Applications (or `~/Applications` when that isn't writable) and
    /// shows the copy in Finder.
    func keepApp() {
        guard !isWorking else { return }

        isWorking = true
        isKeeping = true
        Task {
            do {
                let copy = try await AppInstaller.copy(Bundle.main.originalURL)
                NSWorkspace.shared.activateFileViewerSelecting([copy])
            } catch {
                Logger(subsystem: "com.ruinelson.iamsure", category: "Keep")
                    .error("Couldn't copy the app: \(error.localizedDescription, privacy: .public)")
                keepFailure = error.localizedDescription
            }
            isKeeping = false
            isWorking = false
            processPending()
        }
    }

    /// Entry point for items opened from outside the window (e.g. the "Let me open this App"
    /// Finder action). Queues them until the risks are acknowledged or the current run finishes.
    /// The Finder action sends one item per request, so items arriving within a moment of each
    /// other are processed as one batch.
    func open(_ urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }
        pendingURLs.append(contentsOf: fileURLs.filter { !pendingURLs.contains($0) })
        isReceiving = true

        openGeneration += 1
        let generation = openGeneration
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard generation == openGeneration else { return } // more items arrived meanwhile
            processPending()
        }
    }

    /// Called once launching finishes. Items the app was launched to open arrive before this.
    func finishLaunching() {
        if pendingURLs.isEmpty { isReceiving = false }
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
