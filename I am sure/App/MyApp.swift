import AppKit
import OSLog
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Owned here so items opened from outside the window (see `application(_:open:)`) reach it.
    let model = RemovalModel()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Items sent to the app by Launch Services: the "Let me open this App" Finder action hands
    /// them over this way (it's sandboxed and can't remove quarantine itself), as do drops on
    /// the Dock icon and `open -a`.
    func application(_ application: NSApplication, open urls: [URL]) {
        Self.log.notice("Asked to open \(urls.count) item(s): \(urls.map(\.lastPathComponent), privacy: .public)")
        model.open(urls)
    }

    private static let log = Logger(subsystem: "com.ruinelson.iamsure", category: "Open")
}

@main struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(UserDefaults.acknowledgedRisksKey, store: .shared) var userAcknowledgedPotentialRisks: Bool = false

    private var model: RemovalModel { appDelegate.model }

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
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .result(let result): PresentResult(result: result)
                    case .copy(let request): CopyDestination(request: request)
                    }
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
