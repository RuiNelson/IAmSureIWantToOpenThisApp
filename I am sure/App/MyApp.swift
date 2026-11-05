import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("ackRisks") var userAcknowledgedPotentialRisks: Bool = false
    @State private var model = RemovalModel()

    var body: some Scene {
        // A single window: closing it quits the app (see AppDelegate).
        Window("I am sure I want to open this App", id: "main") {
            NavigationStack(path: Bindable(model).path) {
                Group {
                    if userAcknowledgedPotentialRisks {
                        DropItem()
                    }
                    else {
                        AcknowledgeRisks()
                    }
                }
                .navigationDestination(for: RemoveQuarantineResult.self) { result in
                    PresentResult(result: result)
                }
            }
            .overlay {
                if model.isWorking {
                    ProgressView("Removing quarantine…")
                        .padding(24)
                        .glassEffect(in: .rect(cornerRadius: 20))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.smooth, value: model.isWorking)
            .frame(width: 640, height: 480) // 4:3
            .environment(model)
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
    }
}
