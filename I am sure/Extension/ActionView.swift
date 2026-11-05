import AppKit
import SwiftUI

/// Confirmation sheet shown by the Finder action before handing items to the app.
struct ActionView: View {
    let state: ActionState
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private static let maxItemsShown = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Remove Quarantine?", systemImage: "lock.open.fill")
                .font(.title3.bold())

            content

            Label("Only do this for apps and files you trust, from a source you know.", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.bold())
                .fixedSize(horizontal: false, vertical: true)

            HStack {
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
        .frame(width: 420)
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 48)
        case .handingOff:
            ProgressView("Opening “I am sure”…")
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 48)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        case .ready where state.urls.isEmpty:
            Text("None of the selected items is a file or folder on this Mac.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .ready:
            VStack(alignment: .leading, spacing: 10) {
                Text("“I am sure” will open and remove the `com.apple.quarantine` attribute from \(state.urls.count == 1 ? "this item" : "these items"), including everything inside:")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                itemList
            }
        }
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(state.urls.prefix(Self.maxItemsShown), id: \.self) { url in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 32, height: 32)
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if state.urls.count > Self.maxItemsShown {
                Text("…and \(state.urls.count - Self.maxItemsShown) more")
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

#Preview("Ready") {
    let state = ActionState()
    state.phase = .ready
    state.urls = [
        URL(filePath: "/Applications/Safari.app"),
        URL(filePath: "/Users/Shared/Installer.dmg"),
    ]
    return ActionView(state: state, onCancel: {}, onConfirm: {})
}

#Preview("Failed") {
    let state = ActionState()
    state.phase = .failed("“I am sure” couldn’t be found. Move it to the Applications folder and try again.")
    return ActionView(state: state, onCancel: {}, onConfirm: {})
}
