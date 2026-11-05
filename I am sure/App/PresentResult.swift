//
//  PresentResult.swift
//  I am sure I want to open this App
//
//  Created by Rui Nelson on 05/11/2026.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PresentResult: View {
    let result: RemoveQuarantineResult

    @Environment(RemovalModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 12) {
                LazyVStack(spacing: 12) {
                    ForEach(result.items) { item in
                        ItemResultRow(item: item) {
                            model.path.append(.copy(CopyRequest(urls: [item.url])))
                        }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(in: .rect(cornerRadius: 20))
                    }
                }
            }
            .padding(20)
        }
        .mainToolbar(title: title, subtitle: result.items.count == 1 ? "1 item" : "\(result.items.count) items")
        // Dropping more files here starts a new batch.
        .dropDestination(for: URL.self) { urls, _ in
            model.process(urls)
        } isTargeted: { isTargeted = $0 }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
    }

    private var title: String {
        let failed = result.items.filter { $0.status == .failed }.count
        if failed == 0 { return "Done" }
        return failed == result.items.count ? "Failed" : "Finished with errors"
    }
}

private struct ItemResultRow: View {
    let item: ItemResult
    let onCopy: () -> Void

    private static let maxFailuresShown = 5

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                statusLabel

                if !item.failures.isEmpty {
                    failureList
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if isApp && item.status != .failed {
                    Button("Open") { NSWorkspace.shared.open(item.url) }
                        .buttonStyle(.glassProminent)
                }
                if item.status == .failed {
                    Button("Copy…", action: onCopy)
                        .buttonStyle(.glassProminent)
                        .help("Copy to a writable location and remove quarantine from the copy")
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.glass)
                .help("Show in Finder")
            }
            .frame(maxHeight: 48)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch item.status {
        case .removed:
            Label(
                item.clearedCount == 1
                    ? "Quarantine removed"
                    : "Quarantine removed from \(item.clearedCount) items",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
        case .notQuarantined:
            Label("Wasn’t quarantined", systemImage: "info.circle.fill")
                .foregroundStyle(.secondary)
        case .failed:
            Label(
                item.clearedCount == 0
                    ? "Couldn’t remove quarantine"
                    : "Removed from \(item.clearedCount) items, failed on \(item.failures.count)",
                systemImage: "xmark.octagon.fill"
            )
            .foregroundStyle(.red)
        }
    }

    private var failureList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(item.failures.prefix(Self.maxFailuresShown), id: \.self) { failure in
                Text("\(failure.relativePath.isEmpty ? item.url.lastPathComponent : failure.relativePath): \(failure.message)")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if item.failures.count > Self.maxFailuresShown {
                Text("…and \(item.failures.count - Self.maxFailuresShown) more")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }

    private var isApp: Bool {
        (try? item.url.resourceValues(forKeys: [.contentTypeKey]).contentType)?
            .conforms(to: .application) ?? false
    }
}

#Preview {
    NavigationStack {
        PresentResult(result: .init(items: [
            .init(url: URL(filePath: "/Applications/Safari.app"), clearedCount: 1243, failures: []),
            .init(url: URL(filePath: "/System/Library/CoreServices/Finder.app"), clearedCount: 0, failures: []),
            .init(url: URL(filePath: "/usr/bin/zip"), clearedCount: 0, failures: [
                .init(relativePath: "", message: "Operation not permitted"),
            ]),
        ]))
    }
    .frame(width: 640, height: 480)
    .environment(RemovalModel())
}
