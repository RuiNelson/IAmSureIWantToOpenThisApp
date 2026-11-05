import SwiftUI

/// Same toolbar on every screen so it never pops in when navigating:
/// title, subtitle and a back button that is disabled on the first screen.
private struct MainToolbar: ViewModifier {
    @Environment(RemovalModel.self) private var model

    let title: String
    let subtitle: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        model.path.removeAll()
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                    }
                    .help("Back")
                    .disabled(model.path.isEmpty)
                }
            }
    }
}

extension View {
    func mainToolbar(title: String, subtitle: String) -> some View {
        modifier(MainToolbar(title: title, subtitle: subtitle))
    }
}
