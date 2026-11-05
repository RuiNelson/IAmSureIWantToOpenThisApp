//
//  ActionViewController.swift
//  Let me open this App
//
//  Created by Rui Nelson on 04/11/2026.
//

import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// Finder Quick Action ("Let me open this App").
///
/// App extensions must be sandboxed, and the App Sandbox denies writing the
/// `com.apple.quarantine` attribute, so this extension can't remove it itself. It collects the
/// selected files, asks for confirmation and hands them to the containing (unsandboxed) app,
/// which removes quarantine and shows the result.
final class ActionViewController: NSViewController {
    private let state = ActionState()
    private lazy var hosting = NSHostingController(rootView: ActionView(
        state: state,
        onCancel: { [weak self] in self?.cancel() },
        onConfirm: { [weak self] in self?.confirm() }
    ))

    override func loadView() {
        // Finder sizes the sheet from `preferredContentSize` at presentation and ignores later
        // changes (a zero size is never shown), so measure the SwiftUI content once, with the
        // number of rows already known; `ActionView` keeps that size in every phase.
        state.expectedCount = inputItems.reduce(0) { $0 + ($1.attachments?.count ?? 0) }
        state.showsWarning = !SharedDefaults.risksAcknowledged
        addChild(hosting)
        let size = hosting.view.fittingSize
        hosting.view.frame = NSRect(origin: .zero, size: size)
        hosting.view.autoresizingMask = [.width, .height]

        let container = NSView(frame: hosting.view.frame)
        container.addSubview(hosting.view)
        view = container
        preferredContentSize = size
    }

    private var inputItems: [NSExtensionItem] {
        extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let items = inputItems
        Log.extension.notice("Request with \(items.count) item(s), preferred size \(self.preferredContentSize.debugDescription, privacy: .public)")
        Task {
            state.urls = await FileURLLoader.fileURLs(in: items)
            state.phase = .ready
            Log.extension.notice("Loaded \(self.state.urls.count) file URL(s)")
        }
    }

    private func confirm() {
        guard !state.urls.isEmpty, let appURL = ContainingApp.url else {
            state.phase = .failed("“I am sure” couldn’t be found. Move it to the Applications folder and try again.")
            return
        }

        state.phase = .handingOff
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.promptsUserIfNeeded = false
        let urls = state.urls
        Task {
            do {
                // One request per item: Launch Services sends app bundles in a separate event
                // from other items, and when both go in one request only one of them arrives.
                // The app collects items arriving in quick succession into a single batch.
                for url in urls {
                    _ = try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
                }
                // Nothing changes in Finder: the app does the work and shows the result.
                extensionContext?.completeRequest(returningItems: nil)
            } catch {
                Log.extension.error("Handing items to the app failed: \(error.localizedDescription, privacy: .public)")
                state.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
}

// MARK: - State

@MainActor @Observable final class ActionState {
    enum Phase: Equatable {
        case loading
        case ready
        case handingOff
        case failed(String)
    }

    var phase: Phase = .loading
    var urls: [URL] = []
    /// Number of attachments in the request, known before they're loaded; sizes the sheet.
    var expectedCount = 0
    /// The risk warning is only repeated until it has been acknowledged in the app.
    var showsWarning = true
}

enum Log {
    static let `extension` = Logger(subsystem: "com.ruinelson.iamsure.Let-me-open-this-App", category: "Action")
}

// MARK: - Shared defaults

/// Defaults shared with the app through its App Group (see the entitlements).
enum SharedDefaults {
    static let appGroup = "98DYJ8BJ46.com.ruinelson.iamsure"

    /// Set by the app once the user has acknowledged the risks.
    static var risksAcknowledged: Bool {
        UserDefaults(suiteName: appGroup)?.bool(forKey: "ackRisks") ?? false
    }
}

// MARK: - Containing app

enum ContainingApp {
    static let bundleIdentifier = "com.ruinelson.iamsure"

    /// The app this extension is embedded in (`…/X.app/Contents/PlugIns/Y.appex`), falling back to
    /// whichever copy Launch Services knows about.
    static var url: URL? {
        let embedding = Bundle.main.bundleURL
            .deletingLastPathComponent() // PlugIns
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // X.app
        if embedding.pathExtension == "app", Bundle(url: embedding)?.bundleIdentifier == bundleIdentifier {
            return embedding
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
}

// MARK: - Loading input

/// Extracts file URLs from the extension's input. Finder registers each selected item under its
/// content type (e.g. `com.apple.application-bundle`, `public.folder`), sometimes also as
/// `public.file-url`.
nonisolated enum FileURLLoader {
    static func fileURLs(in items: [NSExtensionItem]) async -> [URL] {
        let providers = items.flatMap { $0.attachments ?? [] }
        var urls: [URL] = []
        for provider in providers {
            guard let url = await fileURL(from: provider) else {
                Log.extension.notice("Skipping attachment with types \(provider.registeredTypeIdentifiers, privacy: .public)")
                continue
            }
            let standardized = url.standardizedFileURL
            if !urls.contains(standardized) { urls.append(standardized) }
        }
        return urls
    }

    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        if provider.canLoadObject(ofClass: URL.self), let url = await loadURLObject(from: provider) {
            return url
        }

        let itemTypes = provider.registeredTypeIdentifiers.filter {
            UTType($0)?.conforms(to: .item) ?? false
        }
        for type in itemTypes {
            if let url = await loadURL(from: provider, type: type) { return url }
        }
        // Only the original location is useful: a copy would be cleared, not the file the user picked.
        for type in itemTypes {
            if let url = await loadInPlaceURL(from: provider, type: type) { return url }
        }
        return nil
    }

    private static func loadURLObject(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url?.isFileURL == true ? url : nil)
            }
        }
    }

    private static func loadURL(from provider: NSItemProvider, type: String) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                let url: URL? = switch item {
                case let url as URL: url
                case let data as Data: URL(dataRepresentation: data, relativeTo: nil)
                case let string as String: URL(string: string)
                default: nil
                }
                continuation.resume(returning: url?.isFileURL == true ? url : nil)
            }
        }
    }

    private static func loadInPlaceURL(from provider: NSItemProvider, type: String) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: type) { url, isInPlace, _ in
                continuation.resume(returning: isInPlace ? url : nil)
            }
        }
    }
}
