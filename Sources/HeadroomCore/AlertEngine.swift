import Foundation

public struct AlertEvaluation: Sendable, Equatable {
    public var active: [Alert]
    public var notify: [Alert]
    public var state: AlertState

    public init(active: [Alert], notify: [Alert], state: AlertState) {
        self.active = active
        self.notify = notify
        self.state = state
    }
}

public enum AlertEngine {
    public static let cooldown: TimeInterval = 30 * 60

    public static func evaluate(
        snapshot: SystemSnapshot,
        settings: HeadroomSettings,
        state: AlertState,
        newlyReviewableBytes: Int64,
        now: Date
    ) -> AlertEvaluation {
        var state = state
        var active: [Alert] = []

        if let volume = snapshot.primaryVolume, volume.totalBytes > 0 {
            let freeGB = Double(volume.freeBytes) / 1_000_000_000
            let freePercent = Double(volume.freeBytes) / Double(volume.totalBytes) * 100
            if freeGB < settings.freeGigabyteThreshold || freePercent < settings.freePercentThreshold {
                active.append(Alert(
                    kind: .disk,
                    title: "Disk space is tight",
                    body: "\(ByteFormat.string(volume.freeBytes)) free on \(volume.name)."
                ))
            }
        }

        if snapshot.memory.pressure == .warning || snapshot.memory.pressure == .urgent || snapshot.memory.pressure == .critical {
            active.append(Alert(
                kind: .memory,
                title: "Memory is \(snapshot.memory.pressure.title.lowercased())",
                body: memoryBody(snapshot)
            ))
        }

        let cpuPercent = snapshot.cpu.usage * 100
        if cpuPercent >= settings.cpuThreshold {
            if state.cpuHighSince == nil { state.cpuHighSince = now }
            if let since = state.cpuHighSince, now.timeIntervalSince(since) >= settings.cpuSustainSeconds {
                active.append(Alert(
                    kind: .cpu,
                    title: "CPU has been high",
                    body: cpuBody(snapshot)
                ))
            }
        } else {
            state.cpuHighSince = nil
        }

        if snapshot.thermal == .serious || snapshot.thermal == .critical {
            active.append(Alert(
                kind: .thermal,
                title: "This Mac is \(snapshot.thermal.title.lowercased())",
                body: cpuBody(snapshot)
            ))
        }

        if newlyReviewableBytes >= 10_000_000_000 {
            active.append(Alert(
                kind: .newJunk,
                title: "A lot of new reviewable space",
                body: "\(ByteFormat.string(newlyReviewableBytes)) showed up since the last map."
            ))
        }

        let notify = active.filter { alert in
            guard let last = state.lastNotified[alert.kind.rawValue] else { return true }
            return now.timeIntervalSince(last) >= cooldown
        }
        for alert in notify {
            state.lastNotified[alert.kind.rawValue] = now
        }
        return AlertEvaluation(active: active, notify: notify, state: state)
    }

    private static func memoryBody(_ snapshot: SystemSnapshot) -> String {
        if let top = snapshot.processes.max(by: { $0.memoryBytes < $1.memoryBytes }) {
            return "\(top.name) is holding \(ByteFormat.string(top.memoryBytes))."
        }
        return "Memory pressure is \(snapshot.memory.pressure.title.lowercased())."
    }

    private static func cpuBody(_ snapshot: SystemSnapshot) -> String {
        if let top = snapshot.processes.max(by: { $0.cpuPercent < $1.cpuPercent }), top.cpuPercent >= 5 {
            return "\(top.name) is using \(Int(top.cpuPercent.rounded()))% CPU."
        }
        return "CPU is at \(Int((snapshot.cpu.usage * 100).rounded()))%."
    }
}

public enum PostcardMaker {
    public static func shouldSend(now: Date, lastSent: Date?, enabled: Bool, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        guard weekday == 2, hour >= 9 else { return false }
        guard let lastSent else { return true }
        return !calendar.isDate(lastSent, equalTo: now, toGranularity: .weekOfYear)
    }

    public static func make(
        now: Date,
        lastScan: ScanResult?,
        previous: ScanResult?,
        freedThisWeek: Int64,
        calendar: Calendar = .current
    ) -> Postcard {
        var lines: [String] = []
        if freedThisWeek > 0 {
            lines.append("You cleared \(ByteFormat.string(freedThisWeek)) this week.")
        } else {
            lines.append("Nothing has been moved to the Trash this week.")
        }
        if let lastScan, let previous {
            let deltas = ScanDiff.topLevelDeltas(previous: previous.tree, current: lastScan.tree)
            if let top = deltas.first {
                let direction = top.bytes >= 0 ? "grew" : "shrank"
                lines.append("\(top.name) \(direction) by \(ByteFormat.string(abs(top.bytes))).")
            }
        } else if lastScan == nil {
            lines.append("The disk has not been mapped yet.")
        }
        if let lastScan, lastScan.safeBytes + lastScan.reviewBytes > 0 {
            lines.append("\(ByteFormat.string(lastScan.safeBytes + lastScan.reviewBytes)) can be reviewed.")
        }
        if lines.isEmpty {
            lines.append("The desk is just watching.")
        }
        let title = "This week"
        _ = calendar
        _ = now
        return Postcard(title: title, lines: lines)
    }
}

public enum Narrative {
    public static func glance(
        snapshot: SystemSnapshot,
        reviewBytes: Int64
    ) -> String {
        var sentences: [String] = []
        if let top = snapshot.processes.max(by: { $0.cpuPercent < $1.cpuPercent }), top.cpuPercent >= 15 {
            sentences.append("\(top.name) is using \(Int(top.cpuPercent.rounded()))% of the CPU.")
        } else if snapshot.cpu.usage < 0.25 {
            sentences.append("CPU is quiet.")
        } else {
            sentences.append("CPU is at \(Int((snapshot.cpu.usage * 100).rounded()))%.")
        }
        switch snapshot.memory.pressure {
        case .normal:
            sentences.append("Memory is calm.")
        case .warning, .urgent, .critical:
            if let hog = snapshot.processes.max(by: { $0.memoryBytes < $1.memoryBytes }) {
                sentences.append("Memory is \(snapshot.memory.pressure.title.lowercased()). \(hog.name) is holding \(ByteFormat.string(hog.memoryBytes)).")
            } else {
                sentences.append("Memory is \(snapshot.memory.pressure.title.lowercased()).")
            }
        }
        if reviewBytes > 0 {
            sentences.append("\(ByteFormat.string(reviewBytes)) can be reviewed.")
        }
        return sentences.joined(separator: " ")
    }

    public static func warmth(_ snapshot: SystemSnapshot) -> String {
        let thermal = snapshot.thermal.title.lowercased()
        if let top = snapshot.processes.max(by: { $0.cpuPercent < $1.cpuPercent }), top.cpuPercent >= 8 {
            return "The Mac feels \(thermal). \(top.name) is the busy one, at \(Int(top.cpuPercent.rounded()))% CPU. Memory is \(snapshot.memory.pressure.title.lowercased())."
        }
        return "The Mac feels \(thermal). No single app is dominating the CPU. Memory is \(snapshot.memory.pressure.title.lowercased())."
    }
}
