import AppKit
import SwiftUI

@main
struct HeadroomApp: App {
    @NSApplicationDelegateAdaptor(HeadroomDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            GlanceView()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

final class HeadroomDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
