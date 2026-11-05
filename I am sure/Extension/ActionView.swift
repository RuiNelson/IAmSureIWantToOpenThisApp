import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Confirmation sheet shown by the Finder action before handing items to the app.
///
/// Finder sizes the sheet from the first layout and doesn't follow later size changes, so the
/// layout never grows after it appears: while loading, one placeholder row is drawn per
/// attachment (the number is known up front), and progress and errors reuse existing space.
struct ActionView: View {
    let state: ActionState
    let onCancel: () -> Void
    let onConfirm: () -> Void

    static let maxItemsShown = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Remove Quarantine?", systemImage: "lock.open.fill")
                .font(.title3.bold())

            content

            if state.showsWarning {
                Label("Only do this for apps and files you trust, from a source you know.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.bold())
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if state.phase == .handingOff {
                    ProgressView().controlSize(.small)
                    Text("Opening “I am sure”...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glass)
                Button("Remove Quarantine", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(state.phase != .ready || state.urls.isEmpty)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 420, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .failed(let message):
            notice(message, systemImage: "xmark.octagon.fill", style: .red)
        case .ready where state.urls.isEmpty:
            notice("None of the selected items is a file or folder on this Mac.", systemImage: "questionmark.folder", style: .secondary)
        case .loading:
            listSection(rows: placeholderRows, total: state.expectedCount)
        case .ready, .handingOff:
            listSection(rows: state.urls.prefix(Self.maxItemsShown).map(Row.init), total: state.urls.count)
        }
    }

    private func notice(_ text: String, systemImage: String, style: some ShapeStyle) -> some View {
        Label(text, systemImage: systemImage)
            .foregroundStyle(style)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func listSection(rows: [Row], total: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("“I am sure” will open and remove the `com.apple.quarantine` attribute from \(total == 1 ? "this item" : "these items"), including everything inside:")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Image(nsImage: row.icon)
                            .resizable()
                            .frame(width: 32, height: 32)
                        Text(row.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .redacted(reason: row.url == nil ? .placeholder : [])
                }
                if total > Self.maxItemsShown {
                    Text("...and \(total - Self.maxItemsShown) more")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 42)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(in: .rect(cornerRadius: 16))
        }
    }

    private var placeholderRows: [Row] {
        (0..<min(max(state.expectedCount, 1), Self.maxItemsShown)).map(Row.init(placeholder:))
    }

    private struct Row: Identifiable {
        let id: String
        let url: URL?
        let name: String
        let icon: NSImage

        init(_ url: URL) {
            id = url.path
            self.url = url
            name = url.lastPathComponent
            icon = NSWorkspace.shared.icon(forFile: url.path)
        }

        init(placeholder index: Int) {
            id = "placeholder-\(index)"
            url = nil
            name = "Loading selected item"
            icon = NSWorkspace.shared.icon(for: .item)
        }
    }
}

#Preview("Loading") {
    let state = ActionState()
    state.expectedCount = 2
    return ActionView(state: state, onCancel: {}, onConfirm: {})
}

#Preview("Ready") {
    let state = ActionState()
    state.expectedCount = 2
    state.phase = .ready
    state.urls = [
        URL(filePath: "/Applications/Safari.app"),
        URL(filePath: "/Users/Shared/Installer.dmg"),
    ]
    return ActionView(state: state, onCancel: {}, onConfirm: {})
}

#Preview("Failed") {
    let state = ActionState()
    state.expectedCount = 1
    state.phase = .failed("“I am sure” couldn’t be found. Move it to the Applications folder and try again.")
    return ActionView(state: state, onCancel: {}, onConfirm: {})
}
