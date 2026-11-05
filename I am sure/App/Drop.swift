//
//  Drop.swift
//  I am sure I want to open this App
//
//  Created by Rui Nelson on 05/11/2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct DropItem: View {
    @Environment(RemovalModel.self) private var model

    @State private var isTargeted = false
    @State private var isImporting = false

    private let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            VStack(spacing: 20) {
                dropZone

                Button { isImporting = true } label: {
                    Label("Choose Files…", systemImage: "folder")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(model.isWorking)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mainToolbar(title: "Select Items", subtitle: "")
        .navigationTitle("Let me open this App")
        .dropDestination(for: URL.self) { urls, _ in
            model.process(urls)
        } isTargeted: { isTargeted = $0 }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { model.process(urls) }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: isTargeted ? "arrow.down.app.fill" : "arrow.down.app")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .contentTransition(.symbolEffect(.replace))

            Text("Drop apps or files here")
                .font(.title2.weight(.semibold))

            Text("Several at once is fine. The `com.apple.quarantine` attribute\nwill be removed from each one, including everything inside.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            shape
                .inset(by: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [10, 8])
                )
        }
        .glassEffect(
            isTargeted ? .regular.tint(.accentColor.opacity(0.3)).interactive() : .regular.interactive(),
            in: shape
        )
        .scaleEffect(isTargeted ? 1.02 : 1)
        .animation(.smooth, value: isTargeted)
    }
}

#Preview {
    NavigationStack {
        DropItem()
    }
    .frame(width: 640, height: 480)
    .environment(RemovalModel())
}
