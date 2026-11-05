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

            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    option(.applications, title: "Applications", symbol: "app.dashed", folder: Self.applications)
                    option(.desktop, title: "Desktop", symbol: "menubar.dock.rectangle", folder: Self.desktop)
                    option(.downloads, title: "Downloads", symbol: "arrow.down.circle", folder: Self.downloads)
                    customOption
                }
            }

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
        .mainToolbar(title: "Copy to…", subtitle: "")
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
            Image(systemName: "externaldrive.badge.xmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.orange)
                .frame(width: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("The original can’t be modified in place, for example because it’s on a read-only disk image. Copy it to a writable location and remove quarantine from the copy?")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var title: String {
        guard let first = request.urls.first else { return "Copy to a writable location" }
        let name = "“\(first.lastPathComponent)”"
        return request.urls.count == 1 ? "Copy \(name)" : "Copy \(name) and \(request.urls.count - 1) more"
    }

    // MARK: Options

    private func option(_ value: Choice, title: String, symbol: String, folder: URL) -> some View {
        let writable = isWritable(folder)
        return OptionRow(
            isSelected: choice == value,
            isEnabled: writable,
            symbol: symbol,
            title: title,
            subtitle: writable ? displayPath(folder) : "Not writable"
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
            subtitle: customFolder.map(displayPath) ?? "Choose any folder…",
            accessory: {
                Button(customFolder == nil ? "Choose…" : "Change…") { isChoosingFolder = true }
                    .buttonStyle(.glass)
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

/// A selectable row with a radio indicator.
private struct OptionRow<Accessory: View>: View {
    let isSelected: Bool
    let isEnabled: Bool
    let symbol: String
    let title: String
    let subtitle: String
    @ViewBuilder var accessory: Accessory
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .contentTransition(.symbolEffect(.replace))

            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            accessory
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect(cornerRadius: 16))
        .onTapGesture { if isEnabled { action() } }
        .glassEffect(
            isSelected ? .regular.tint(.accentColor.opacity(0.25)) : .regular,
            in: .rect(cornerRadius: 16)
        )
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.smooth, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension OptionRow where Accessory == EmptyView {
    init(isSelected: Bool, isEnabled: Bool, symbol: String, title: String, subtitle: String, action: @escaping () -> Void) {
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
