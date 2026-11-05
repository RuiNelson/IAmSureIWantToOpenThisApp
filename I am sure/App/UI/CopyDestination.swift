import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Asks where to copy items that couldn't be modified in place (e.g. on a read-only disk image).
struct CopyDestination: View {
    let request: CopyRequest

    @Environment(RemovalModel.self) private var model

    private enum Choice: Hashable {
        case applications, desktop, downloads, custom
    }

    @State private var choice: Choice = .applications
    @State private var customFolder: URL?
    @State private var isChoosingFolder = false

    private static let applications = FileManager.default
        .urls(for: .applicationDirectory, in: .localDomainMask).first ?? URL(filePath: "/Applications")
    private static let desktop = FileManager.default
        .urls(for: .desktopDirectory, in: .userDomainMask).first ?? URL(filePath: NSHomeDirectory())
    private static let downloads = FileManager.default
        .urls(for: .downloadsDirectory, in: .userDomainMask).first ?? URL(filePath: NSHomeDirectory())

    var body: some View {
        VStack(spacing: 18) {
            header

            VStack(spacing: 14) {
                option(.applications, title: "Applications", symbol: "app.badge.checkmark", folder: Self.applications)
                option(.desktop, title: "Desktop", symbol: "menubar.dock.rectangle", folder: Self.desktop)
                option(.downloads, title: "Downloads", symbol: "arrow.down.circle", folder: Self.downloads)
                customOption
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 0)

            HStack {
                Button("Cancel") { model.path.removeLast() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glass)

                Spacer()

                Button("Copy and Remove Quarantine") {
                    if let destination { model.copyAndProcess(request.urls, to: destination) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
                .disabled(destination == nil)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mainToolbar(title: "Copy to...", subtitle: "")
        .onAppear {
            if !isWritable(Self.applications) { choice = .downloads }
        }
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { picked in
            if case .success(let folder) = picked {
                customFolder = folder
                choice = .custom
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: request.urls.first?.path ?? ""))
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Text("The original can’t be modified in place. Copy it to a writable location and remove quarantine from the copy?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
    }

    private var title: LocalizedStringKey {
        guard let first = request.urls.first else { return "Copy to a writable location" }
        let name = "“\(first.lastPathComponent)”"
        return request.urls.count == 1 ? "Copy \(name)?" : "Copy \(name) and \(request.urls.count - 1) more?"
    }

    // MARK: Options

    private func option(_ value: Choice, title: LocalizedStringKey, symbol: String, folder: URL) -> some View {
        let writable = isWritable(folder)
        return OptionRow(
            isSelected: choice == value,
            isEnabled: writable,
            symbol: symbol,
            title: title,
            subtitle: writable ? Text(verbatim: displayPath(folder)) : Text("Not writable")
        ) {
            choice = value
        }
    }

    private var customOption: some View {
        OptionRow(
            isSelected: choice == .custom,
            isEnabled: true,
            symbol: "folder",
            title: "Custom Location",
            subtitle: customFolder.map { Text(verbatim: displayPath($0)) } ?? Text("Choose any folder..."),
            accessory: {
                Button(customFolder == nil ? "Choose..." : "Change...") { isChoosingFolder = true }
                    .buttonStyle(.bordered)
            }
        ) {
            // First pick opens the folder chooser right away.
            if customFolder == nil {
                isChoosingFolder = true
            } else {
                choice = .custom
            }
        }
    }

    // MARK: Helpers

    private var destination: URL? {
        switch choice {
        case .applications: Self.applications
        case .desktop: Self.desktop
        case .downloads: Self.downloads
        case .custom: customFolder
        }
    }

    private func isWritable(_ url: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: url.path)
    }

    private func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}

/// A radio-style option: a round glass button (clear when off, accent-tinted when on) beside its label.
private struct OptionRow<Accessory: View>: View {
    let isSelected: Bool
    let isEnabled: Bool
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: Text
    @ViewBuilder var accessory: Accessory
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : .primary)
                    .frame(width: 48, height: 48)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .glassEffect(
                // Same glass variant in both states: only the tint changes, so it animates
                // instead of swapping materials (which flashes).
                .clear.tint(isSelected ? Color.accentColor : nil).interactive(),
                in: .circle
            )
            .animation(.smooth, value: isSelected)

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                subtitle
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            accessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .onTapGesture(perform: action)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension OptionRow where Accessory == EmptyView {
    init(isSelected: Bool, isEnabled: Bool, symbol: String, title: LocalizedStringKey, subtitle: Text, action: @escaping () -> Void) {
        self.init(
            isSelected: isSelected, isEnabled: isEnabled, symbol: symbol, title: title,
            subtitle: subtitle, accessory: { EmptyView() }, action: action
        )
    }
}

#Preview {
    NavigationStack {
        CopyDestination(request: CopyRequest(urls: [URL(filePath: "/Volumes/Installer/Some App.app")]))
    }
    .frame(width: 640, height: 480)
    .environment(RemovalModel())
}
