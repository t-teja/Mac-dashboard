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
        .help(helpText)
    }

    private var helpText: String {
        if model.settings.stayAwake {
            return Brand.name + ". " + AwakeSchedule.status(until: model.settings.awakeUntil)
        }
        return model.hasAlert ? (model.activeAlerts.first?.title ?? Brand.name) : Brand.name
    }

    private var icon: NSImage {
        let cores = model.settings.showCoresInMenuBar ? Array(model.snapshot.cpu.cores.prefix(8)) : []
        let awake = model.settings.stayAwake
        let width = 18 + CGFloat(cores.count) * 3
        let image = NSImage(size: NSSize(width: width, height: 16), flipped: false) { _ in
            let planet = NSBezierPath(ovalIn: CGRect(x: 3.6, y: 3.4, width: 9, height: 9))
            NSColor.black.setStroke()
            planet.lineWidth = 1.35
            planet.stroke()
            let ring = NSBezierPath(ovalIn: CGRect(x: 1.1, y: 5.4, width: 14.2, height: 4.8))
            ring.lineWidth = 1.15
            ring.stroke()
            if awake {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: CGRect(x: 13.4, y: 11.6, width: 3.1, height: 3.1)).fill()
            }
            for (index, core) in cores.enumerated() {
                let barHeight = CGFloat(max(2.0, 13.0 * core.usage))
                let rect = CGRect(x: 20 + CGFloat(index * 3), y: 1.5, width: 2, height: barHeight)
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
                Text(Brand.name)
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

            stayAwake

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
            Text("Map home reads folder names and sizes on this Mac. Denying a folder prompt leaves that folder out.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
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

    private var stayAwake: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Stay awake", isOn: Binding(
                get: { model.settings.stayAwake },
                set: { model.setStayAwake($0) }
            ))
            .toggleStyle(.switch)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.cream)
            Text(model.settings.stayAwake
                 ? AwakeSchedule.status(until: model.settings.awakeUntil)
                 : "Stops idle sleep so agents and background work keep running. The display can still turn off.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            if model.settings.stayAwake {
                AwakeChoiceControl(selection: model.settings.awakeChoice) { choice in
                    model.setAwakeChoice(choice)
                }
                Toggle("Keep the display on", isOn: Binding(
                    get: { model.settings.keepDisplayOn },
                    set: { value in model.updateSettings { $0.keepDisplayOn = value } }
                ))
                .toggleStyle(.switch)
                .font(.system(size: 12))
                .foregroundStyle(Theme.cream)
            }
        }
        .tint(Theme.brass)
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
