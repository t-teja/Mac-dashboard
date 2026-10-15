import AppKit
import HeadroomCore
import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: icon)
            if model.hasAlert {
                Circle().fill(Theme.coral).frame(width: 6, height: 6)
            }
            Text(model.menuLabel)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .help(model.hasAlert ? (model.activeAlerts.first?.title ?? "Headroom") : "Headroom")
    }

    private var icon: NSImage {
        let cores = model.settings.showCoresInMenuBar ? Array(model.snapshot.cpu.cores.prefix(8)) : []
        let width = 16 + CGFloat(cores.count) * 3
        let image = NSImage(size: NSSize(width: width, height: 16), flipped: false) { _ in
            let ring = NSBezierPath(ovalIn: CGRect(x: 1.5, y: 1.5, width: 13, height: 13))
            NSColor.black.withAlphaComponent(0.28).setStroke()
            ring.lineWidth = 1.6
            ring.stroke()
            let fraction = model.snapshot.primaryVolume?.freeFraction ?? 0
            if fraction > 0.02 {
                let arc = NSBezierPath()
                let start = 150.0 * Double.pi / 180
                let end = start + (240.0 * min(1, fraction)) * Double.pi / 180
                arc.appendArc(withCenter: CGPoint(x: 8, y: 8), radius: 6.5, startAngle: start, endAngle: end, clockwise: false)
                NSColor.black.setStroke()
                arc.lineWidth = 1.8
                arc.lineCapStyle = .round
                arc.stroke()
            }
            for (index, core) in cores.enumerated() {
                let barHeight = CGFloat(max(2.0, 13.0 * core.usage))
                let rect = CGRect(x: 18 + CGFloat(index * 3), y: 1.5, width: 2, height: barHeight)
                NSColor.black.withAlphaComponent(0.35 + 0.65 * core.usage).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct GlanceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HotkeyOpener()
            HStack {
                Text("Headroom")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.cream)
                Spacer()
                if model.hasAlert {
                    Circle().fill(Theme.coral).frame(width: 8, height: 8)
                }
            }
            ArcGauge(fraction: model.snapshot.primaryVolume?.freeFraction ?? 0)
                .frame(width: 168, height: 168)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text(freeLine)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.cream)
                    .contentTransition(.numericText())
                Text(detailLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
            }
            Text(Narrative.glance(snapshot: model.snapshot, reviewBytes: model.reviewBytes))
                .font(.system(size: 13))
                .foregroundStyle(Theme.cream.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)

            Meter(
                title: "CPU",
                value: "\(Int((model.snapshot.cpu.usage * 100).rounded()))%",
                fraction: model.snapshot.cpu.usage,
                tint: Theme.brass
            )
            Meter(
                title: "Memory",
                value: "\(Int((model.snapshot.memory.usedFraction * 100).rounded()))%",
                fraction: model.snapshot.memory.usedFraction,
                tint: Theme.lilac
            )
            HStack {
                Text(model.snapshot.thermal.title)
                    .foregroundStyle(model.snapshot.thermal == .nominal ? Theme.sage : Theme.coral)
                Spacer()
                if let battery = model.snapshot.battery {
                    Text("\(Int((battery.percent * 100).rounded()))%\(battery.charging ? " charging" : "")")
                        .foregroundStyle(Theme.dim)
                }
            }
            .font(.system(size: 12, weight: .medium))

            if let alert = model.activeAlerts.first {
                Text(alert.body)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.brass)
            }

            Button("Open the desk") {
                model.presentDesk()
            }
            .buttonStyle(BrassButtonStyle())

            HStack {
                Button("Map home") { model.scanHome() }
                    .buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.dim)
            }
            if !model.alertsAllowed {
                Button("Allow alerts") { model.allowAlerts() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.brass)
            }
        }
        .padding(18)
        .frame(width: 340)
        .background(Theme.ink)
        .preferredColorScheme(.dark)
        .onAppear {
            if model.consumeLaunchRequest() {
                model.presentDesk()
            }
        }
    }

    private var freeLine: String {
        guard let volume = model.snapshot.primaryVolume else { return "Reading disks" }
        return ByteFormat.string(volume.freeBytes) + " free"
    }

    private var detailLine: String {
        guard let volume = model.snapshot.primaryVolume else { return "Volumes are still loading" }
        return "of \(ByteFormat.string(volume.totalBytes)) · \(ByteFormat.string(volume.purgeableBytes)) purgeable"
    }
}
