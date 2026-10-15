import AppKit
import Carbon
import HeadroomCore
import SwiftUI

struct AppsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apps")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.cream)
                        Text("User apps only. Apple’s own apps are hidden. Leftovers stay unchecked until you pick them.")
                            .foregroundStyle(Theme.dim)
                            .font(.system(size: 13))
                    }
                    Spacer()
                    Button(model.loadingApps ? "Looking…" : "Refresh") { model.loadApps() }
                        .buttonStyle(BrassButtonStyle())
                        .disabled(model.loadingApps)
                }
                if model.apps.isEmpty && !model.loadingApps {
                    DeskCard {
                        Text("Refresh to read /Applications and your own Applications folder.")
                            .foregroundStyle(Theme.dim)
                    }
                }
                ForEach(model.apps) { app in
                    AppCard(app: app)
                }
            }
            .padding(28)
        }
        .onAppear {
            if model.apps.isEmpty && !model.loadingApps { model.loadApps() }
        }
    }
}

private struct AppCard: View {
    @Environment(AppModel.self) private var model
    var app: InstalledApp
    @State private var checked: Set<String> = []
    @State private var open = false

    var body: some View {
        DeskCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.cream)
                        Text(app.bundleID).font(.system(size: 11)).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Text(ByteFormat.string(app.bytes)).foregroundStyle(Theme.cream).monospacedDigit()
                    Button("Stage app") { model.stageApp(app, leftoverPaths: checked) }
                        .buttonStyle(QuietButtonStyle())
                }
                if !app.leftovers.isEmpty {
                    Button(open ? "Hide leftovers" : "\(app.leftovers.count) leftovers") { open.toggle() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.brass)
                        .font(.system(size: 12, weight: .medium))
                    if open {
                        ForEach(app.leftovers) { leftover in
                            HStack {
                                Image(systemName: checked.contains(leftover.path) ? "checkmark.square" : "square")
                                    .foregroundStyle(Theme.brass)
                                Text(PathDisplay.string(leftover.path)).font(.system(size: 11)).foregroundStyle(Theme.cream).lineLimit(1)
                                Spacer()
                                Text(ByteFormat.string(leftover.bytes)).foregroundStyle(Theme.dim)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if checked.contains(leftover.path) { checked.remove(leftover.path) }
                                else { checked.insert(leftover.path) }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CloudView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cloud")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.cream)
                        Text("Local footprints only. There is no delete button here, and measuring does not download files.")
                            .foregroundStyle(Theme.dim)
                            .font(.system(size: 13))
                    }
                    Spacer()
                    Button(model.measuringCloud ? "Measuring…" : "Measure local copies") { model.measureClouds() }
                        .buttonStyle(BrassButtonStyle())
                        .disabled(model.measuringCloud || model.clouds.isEmpty)
                }
                if model.clouds.isEmpty {
                    DeskCard {
                        Text("No iCloud Drive, CloudStorage, or Google Drive cache folder was found.")
                            .foregroundStyle(Theme.dim)
                    }
                }
                ForEach(model.clouds) { place in
                    DeskCard {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(place.provider)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.cream)
                                Spacer()
                                Text(place.localBytes.map { ByteFormat.string($0) } ?? "Not measured")
                                    .foregroundStyle(Theme.brass)
                                    .monospacedDigit()
                            }
                            Text(PathDisplay.string(place.path)).font(.system(size: 11)).foregroundStyle(Theme.dim)
                            Text(place.note).font(.system(size: 12)).foregroundStyle(Theme.cream.opacity(0.8))
                        }
                    }
                }
            }
            .padding(28)
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var listening = false

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.cream)
                Text("Mac Space Saver stays on this Mac. It does not have an account, and it does not phone home.")
                    .foregroundStyle(Theme.dim)

                DeskCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Stay awake")
                        Toggle("Keep the Mac from idle sleep", isOn: Binding(
                            get: { model.settings.stayAwake },
                            set: { model.setStayAwake($0) }
                        ))
                        .toggleStyle(.switch)
                        .foregroundStyle(Theme.cream)
                        Text("Use this while an agent or another background job is running. The screen can still sleep. Closing the app lets the Mac sleep on its normal schedule.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                        AwakeChoiceControl(selection: model.settings.awakeChoice) { choice in
                            model.setAwakeChoice(choice)
                        }
                        Toggle("Keep the display on", isOn: Binding(
                            get: { model.settings.keepDisplayOn },
                            set: { value in model.updateSettings { $0.keepDisplayOn = value } }
                        ))
                        .toggleStyle(.switch)
                        .foregroundStyle(Theme.cream)
                        if model.settings.stayAwake {
                            Text(AwakeSchedule.status(until: model.settings.awakeUntil))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.brass)
                        }
                    }
                }

                DeskCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Menu bar")
                        Picker("Show", selection: Binding(
                            get: { model.settings.menuBarMetric },
                            set: { value in model.updateSettings { $0.menuBarMetric = value } }
                        )) {
                            ForEach(MenuBarMetric.allCases, id: \.self) { metric in
                                Text(metric.title).tag(metric)
                            }
                        }
                        .pickerStyle(.segmented)
                        Toggle("Per-core bars", isOn: Binding(
                            get: { model.settings.showCoresInMenuBar },
                            set: { value in model.updateSettings { $0.showCoresInMenuBar = value } }
                        ))
                        .toggleStyle(.switch)
                        .foregroundStyle(Theme.cream)
                    }
                }

                DeskCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Alerts")
                        slider("Free space under", value: Binding(
                            get: { model.settings.freeGigabyteThreshold },
                            set: { value in model.updateSettings { $0.freeGigabyteThreshold = value } }
                        ), range: 5...200, suffix: "GB")
                        slider("Or under", value: Binding(
                            get: { model.settings.freePercentThreshold },
                            set: { value in model.updateSettings { $0.freePercentThreshold = value } }
                        ), range: 2...40, suffix: "%")
                        slider("CPU over", value: Binding(
                            get: { model.settings.cpuThreshold },
                            set: { value in model.updateSettings { $0.cpuThreshold = value } }
                        ), range: 50...100, suffix: "%")
                        Toggle("Monday postcard", isOn: Binding(
                            get: { model.settings.postcardEnabled },
                            set: { value in model.updateSettings { $0.postcardEnabled = value } }
                        ))
                        .foregroundStyle(Theme.cream)
                        Button(model.alertsAllowed ? "Alerts are allowed" : "Allow alerts") { model.allowAlerts() }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(model.alertsAllowed)
                    }
                }

                DeskCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(text: "Startup and shortcut")
                        Toggle("Open Mac Space Saver at login", isOn: Binding(
                            get: { model.launchAtLogin },
                            set: { model.setLaunchAtLogin($0) }
                        ))
                        .foregroundStyle(Theme.cream)
                        if let loginError = model.loginError {
                            Text(loginError).foregroundStyle(Theme.coral).font(.system(size: 12))
                        }
                        Toggle("Shortcut", isOn: Binding(
                            get: { model.settings.hotkeyEnabled },
                            set: { value in model.updateSettings { $0.hotkeyEnabled = value } }
                        ))
                        .foregroundStyle(Theme.cream)
                        HStack {
                            Text(shortcutLabel)
                                .foregroundStyle(Theme.cream)
                            Spacer()
                            Button(listening ? "Press a key" : "Change") { listening = true }
                                .buttonStyle(QuietButtonStyle())
                        }
                        Text("The shortcut stays off until you enable it, so it does not take a key while you are in something else.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                    }
                }

                DeskCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Duplicates")
                        slider("Ignore files under", value: Binding(
                            get: { model.settings.duplicateMinimumMegabytes },
                            set: { value in model.updateSettings { $0.duplicateMinimumMegabytes = value } }
                        ), range: 1...500, suffix: "MB")
                    }
                }
            }
            .padding(28)
            .tint(Theme.brass)
        }
        .background(shortcutCatcher)
    }

    private var shortcutLabel: String {
        var parts: [String] = []
        let mods = model.settings.hotkeyModifiers
        if mods & UInt32(controlKey) != 0 { parts.append("⌃") }
        if mods & UInt32(optionKey) != 0 { parts.append("⌥") }
        if mods & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if mods & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyName(model.settings.hotkeyCode))
        return parts.joined()
    }

    private var shortcutCatcher: some View {
        ShortcutCatcher(listening: $listening) { code, modifiers in
            model.updateSettings {
                $0.hotkeyCode = code
                $0.hotkeyModifiers = modifiers
                $0.hotkeyEnabled = true
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).foregroundStyle(Theme.cream)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded())) \(suffix)")
                    .foregroundStyle(Theme.brass)
                    .monospacedDigit()
            }
            .font(.system(size: 13))
            Slider(value: value, in: range)
                .tint(Theme.brass)
        }
    }

    private func keyName(_ code: UInt32) -> String {
        if code == UInt32(kVK_Space) { return "Space" }
        return "key \(code)"
    }
}

private struct ShortcutCatcher: View {
    @Binding var listening: Bool
    var onCapture: (UInt32, UInt32) -> Void

    var body: some View {
        Color.clear
            .onAppear {}
            .background(CatcherView(listening: $listening, onCapture: onCapture))
    }
}

private struct CatcherView: NSViewRepresentable {
    @Binding var listening: Bool
    var onCapture: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcher()
        view.onKey = { event in
            guard listening else { return }
            var mods: UInt32 = 0
            if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
            if event.modifierFlags.contains(.option) { mods |= UInt32(optionKey) }
            if event.modifierFlags.contains(.shift) { mods |= UInt32(shiftKey) }
            if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
            onCapture(UInt32(event.keyCode), mods)
            listening = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? KeyCatcher)?.armed = listening
    }
}

private final class KeyCatcher: NSView {
    var armed = false
    var onKey: ((NSEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        guard armed else { return }
        onKey?(event)
    }
}
