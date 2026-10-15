import HeadroomCore
import SwiftUI

struct Arc: Shape {
    var start: Double
    var end: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2 - 10
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: .degrees(start),
            endAngle: .degrees(end),
            clockwise: false
        )
        return path
    }
}

struct ArcGauge: View {
    var fraction: Double

    var body: some View {
        ZStack {
            Arc(start: 140, end: 400)
                .stroke(Theme.line, style: StrokeStyle(lineWidth: 14, lineCap: .round))
            Arc(start: 140, end: 140 + 260 * min(1, max(0, fraction)))
                .stroke(Theme.brass, style: StrokeStyle(lineWidth: 14, lineCap: .round))
        }
    }
}

struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(Theme.dim)
    }
}

struct Meter: View {
    var title: String
    var value: String
    var fraction: Double
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).foregroundStyle(Theme.dim)
                Spacer()
                Text(value).foregroundStyle(Theme.cream).monospacedDigit()
            }
            .font(.system(size: 12, weight: .medium))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill(tint).frame(width: max(4, geo.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: 6)
        }
    }
}

struct Pill: View {
    var text: String
    var tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule())
    }
}

struct DeskCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }
}

struct BrassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.brass.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.cream)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.raised.opacity(configuration.isPressed ? 1 : 0.7), in: Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
    }
}

/// Duration choices drawn as labels. A system menu picker paints an empty black bar in the menu-bar panel.
struct AwakeChoiceControl: View {
    var selection: AwakeChoice
    var onSelect: (AwakeChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("For")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.dim)
            chip(.untilOff)
            HStack(spacing: 6) {
                chip(.minutes30)
                chip(.hour1)
                chip(.hours2)
            }
            chip(.untilMorning)
        }
    }

    private func chip(_ choice: AwakeChoice) -> some View {
        let selected = selection == choice
        return Button {
            onSelect(choice)
        } label: {
            Text(choice.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? Theme.ink : Theme.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(selected ? Theme.brass : Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selected ? Theme.brass : Theme.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct StrataStrip: View {
    var slices: [(DiskCategory, Int64)]

    var body: some View {
        let total = slices.reduce(Int64(0)) { $0 + $1.1 }
        GeometryReader { geo in
            HStack(spacing: 3) {
                if total <= 0 {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.line)
                } else {
                    ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Theme.color(for: slice.0))
                            .frame(width: max(4, geo.size.width * CGFloat(slice.1) / CGFloat(total)))
                            .help("\(slice.0.title) · \(ByteFormat.string(slice.1))")
                    }
                }
            }
        }
        .frame(height: 28)
    }
}

struct OrganPipes: View {
    var cores: [CoreSample]

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(cores) { core in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(core.isEfficiency ? Theme.brass : Theme.cream)
                        .frame(height: max(6, 110 * core.usage))
                        .frame(maxWidth: .infinity)
                        .help("Core \(core.index) · \(Int((core.usage * 100).rounded()))%")
                    Text("\(core.index)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
        .frame(height: 132, alignment: .bottom)
        .animation(.easeOut(duration: 0.35), value: cores.map(\.usage))
    }
}

struct HotkeyOpener: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: model.hotkeyPulse) { _, _ in
                model.presentDesk()
            }
    }
}

enum PathDisplay {
    static func string(_ path: String) -> String {
        SecurityGate.displayPath(path, home: NSHomeDirectory())
    }

    static func shortName(_ path: String, fallback: String) -> String {
        if path.hasSuffix("::other") { return fallback }
        let shown = string(path)
        if shown == "~" { return "Home" }
        let name = (shown as NSString).lastPathComponent
        return name.isEmpty ? fallback : name
    }
}

enum NodeFind {
    static func find(_ node: FileNode, path: String) -> FileNode? {
        if node.path == path { return node }
        for child in node.children {
            if let found = find(child, path: path) { return found }
        }
        return nil
    }

    static func strata(_ node: FileNode, home: String) -> [(DiskCategory, Int64)] {
        var totals: [DiskCategory: Int64] = [:]
        for child in node.children where !child.path.hasSuffix("::other") {
            let category = Classifier.category(for: child.path, home: home)
            totals[category, default: 0] += child.allocatedBytes
        }
        return DiskCategory.allCases.compactMap { category in
            guard let bytes = totals[category], bytes > 0 else { return nil }
            return (category, bytes)
        }
    }
}
