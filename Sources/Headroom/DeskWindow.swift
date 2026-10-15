import AppKit
import SwiftUI

enum DeskWindow {
    @MainActor
    static func present(model: AppModel) {
        model.prepareDesk()
        if let window = model.deskWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingView(rootView: DashboardView().environment(model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Headroom"
        window.contentView = host
        window.minSize = NSSize(width: 1040, height: 700)
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(srgbRed: 16.0 / 255, green: 18.0 / 255, blue: 24.0 / 255, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        model.deskWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.environment["HEADROOM_REPORT"] != nil {
            writeReport(model: model, window: window)
        }
    }

    @MainActor
    private static func writeReport(model: AppModel, window: NSWindow) {
        guard let path = ProcessInfo.processInfo.environment["HEADROOM_REPORT"] else { return }
        let base = URL(fileURLWithPath: path).deletingPathExtension()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            var lines = ["frame=\(window.frame)"]
            for page in DeskPage.allCases {
                model.page = page
                try? await Task.sleep(nanoseconds: 400_000_000)
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                if let png = capture(window) {
                    let url = base.appendingPathExtension(page.rawValue).appendingPathExtension("png")
                    try? png.write(to: url)
                    lines.append("png \(page.rawValue) bytes=\(png.count)")
                } else {
                    lines.append("png \(page.rawValue) FAILED")
                }
            }
            model.page = .overview
            lines.append("visible=\(window.isVisible) key=\(window.isKeyWindow)")
            lines.append("scanning=\(model.scanning) duplicates=\(model.scanningDuplicates) images=\(model.loadingImages) apps=\(model.loadingApps) cloud=\(model.measuringCloud)")
            lines.append("removing=\(model.removing) bin=\(model.bin.count) showConfirm=\(model.showConfirm)")
            lines.append("cpu=\(model.snapshot.cpu.usage) cores=\(model.snapshot.cpu.cores.count) pressure=\(model.snapshot.memory.pressure)")
            lines.append("memoryApp=\(model.snapshot.memory.appBytes) free=\(model.snapshot.memory.freeBytes)")
            lines.append("volumes=" + model.snapshot.volumes.map { "\($0.name) total=\($0.totalBytes) free=\($0.freeBytes)" }.joined(separator: " | "))
            lines.append("alerts=" + model.activeAlerts.map { "\($0.kind) \($0.title)" }.joined(separator: " ; "))
            lines.append("windows=" + NSApp.windows.map { "title=\($0.title) visible=\($0.isVisible) level=\($0.level.rawValue)" }.joined(separator: " ; "))
            try? lines.joined(separator: "\n").write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            window.orderOut(nil)
            let stillOpen = NSApp.windows.contains { $0.title == "Headroom" && $0.isVisible }
            if !stillOpen {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    @MainActor
    private static func capture(_ window: NSWindow) -> Data? {
        guard let view = window.contentView else { return nil }
        let bounds = view.bounds
        guard bounds.width > 2, bounds.height > 2 else { return nil }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
