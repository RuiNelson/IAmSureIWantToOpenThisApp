//
//  ActionRequestHandler.swift
//  Let me open this App
//
//  Created by Rui Nelson on 04/11/2026.
//

import AppKit
import OSLog
import UniformTypeIdentifiers

/// Finder Quick Action ("Let me open this App"), without a user interface.
///
/// App extensions must be sandboxed, and the App Sandbox denies writing the
/// `com.apple.quarantine` attribute, so this extension can't remove it itself. It hands the
/// selected items to the containing (unsandboxed) app, which asks for the risks to be
/// acknowledged if needed, removes quarantine and shows the result.
final class ActionRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let providers = context.inputItems.flatMap { ($0 as? NSExtensionItem)?.attachments ?? [] }
        Task {
            do {
                let urls = await FileURLLoader.fileURLs(from: providers)
                try await ContainingApp.open(urls)
                // Nothing changes in Finder: the app does the work and shows the result.
                context.completeRequest(returningItems: nil)
            } catch {
                Log.action.error("Request failed: \(error.localizedDescription, privacy: .public)")
                context.cancelRequest(withError: error)
            }
        }
    }
}

enum Log {
    static let action = Logger(subsystem: "com.ruinelson.iamsure.Let-me-open-this-App", category: "Action")
}

// MARK: - Containing app

enum ContainingApp {
    static let bundleIdentifier = "com.ruinelson.iamsure"

    /// Opens `urls` in the containing app, which brings it to the front.
    static func open(_ urls: [URL]) async throws {
        guard !urls.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        guard let appURL = url else { throw CocoaError(.fileNoSuchFile) }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.promptsUserIfNeeded = false
        // One request per item: Launch Services sends app bundles in a separate event from other
        // items, and when both go in one request only one of them arrives. The app collects items
        // arriving in quick succession into a single batch.
        for url in urls {
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
        }
        Log.action.notice("Handed \(urls.count) item(s) to the app")
    }

    /// The app this extension is embedded in (`.../X.app/Contents/PlugIns/Y.appex`), falling back to
    /// whichever copy Launch Services knows about.
    private static var url: URL? {
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
enum FileURLLoader {
    /// Loads all attachments concurrently; the result keeps the selection's order, without duplicates.
    static func fileURLs(from providers: [NSItemProvider]) async -> [URL] {
        let loaded = await withTaskGroup(of: (Int, URL?).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask { (index, await fileURL(from: provider)) }
            }
            var urls = [URL?](repeating: nil, count: providers.count)
            for await (index, url) in group { urls[index] = url }
            return urls
        }

        var seen = Set<URL>()
        return zip(providers, loaded).compactMap { provider, url in
            guard let url = url?.standardizedFileURL else {
                Log.action.notice("Skipping attachment with types \(provider.registeredTypeIdentifiers, privacy: .public)")
                return nil
            }
            return seen.insert(url).inserted ? url : nil
        }
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
