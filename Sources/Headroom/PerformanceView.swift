import Charts
import Darwin
import HeadroomCore
import SwiftUI

struct PerformanceView: View {
    @Environment(AppModel.self) private var model
    @State private var sortMemory = false
    @State private var forcePID: Int32?
    @State private var forceName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Performance")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.cream)
                Text(Narrative.warmth(model.snapshot))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)

                DeskCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Cores")
                        if model.snapshot.cpu.cores.isEmpty {
                            Text("Waiting for a second of CPU time.")
                                .foregroundStyle(Theme.dim)
                        } else {
                            OrganPipes(cores: model.snapshot.cpu.cores)
                            Text("Cream bars are performance cores. Brass bars are efficiency cores.")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                }

                HStack(spacing: 12) {
                    memoryCard
                    sparkCard(title: "CPU", keyPath: \.cpu, tint: Theme.brass, unit: "%")
                }
                HStack(spacing: 12) {
                    rateCard(title: "Disk", read: model.snapshot.diskIO.readBytesPerSecond, write: model.snapshot.diskIO.writeBytesPerSecond, readKey: \.diskRead, writeKey: \.diskWrite)
                    rateCard(title: "Network", read: model.snapshot.network.inBytesPerSecond, write: model.snapshot.network.outBytesPerSecond, readKey: \.netIn, writeKey: \.netOut)
                }

                HStack(spacing: 12) {
                    DeskCard {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(text: "Warmth")
                            Text(model.snapshot.thermal.title)
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.cream)
                            Text("Up \(TimeFormat.uptime(model.snapshot.uptime))")
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    DeskCard {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(text: "Battery")
                            if let battery = model.snapshot.battery {
                                Text("\(Int((battery.percent * 100).rounded()))%")
                                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.cream)
                                Text(batteryLine(battery))
                                    .foregroundStyle(Theme.dim)
                            } else {
                                Text("No battery")
                                    .foregroundStyle(Theme.dim)
                            }
                        }
                    }
                }

                HStack {
                    SectionLabel(text: "Processes")
                    Spacer()
                    Picker("Sort", selection: $sortMemory) {
                        Text("CPU").tag(false)
                        Text("Memory").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                Text("Quit, pause, and priority only work on your own apps. macOS has no safe per-app CPU percent cap, so Low priority is a nice value, not a quota.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)

                ForEach(processes) { process in
                    processRow(process)
                }
            }
            .padding(28)
        }
        .confirmationDialog("Force quit \(forceName)?", isPresented: forcePresented, titleVisibility: .visible) {
            Button("Force quit", role: .destructive) {
                model.control(.forceQuit, pid: forcePID ?? -1)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unsaved work in that app is lost. System processes are refused.")
        }
    }

    private var forcePresented: Binding<Bool> {
        Binding(get: { forcePID != nil }, set: { if !$0 { forcePID = nil } })
    }

    private var processes: [ProcessSample] {
        if sortMemory {
            return model.snapshot.processes.sorted { $0.memoryBytes > $1.memoryBytes }
        }
        return model.snapshot.processes
    }

    private var memoryCard: some View {
        DeskCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Memory")
                memoryBand
                labeled("App", model.snapshot.memory.appBytes)
                labeled("Wired", model.snapshot.memory.wiredBytes)
                labeled("Compressed", model.snapshot.memory.compressedBytes)
                labeled("Cached", model.snapshot.memory.cachedBytes)
                Text(model.snapshot.memory.pressure.title)
                    .foregroundStyle(model.snapshot.memory.pressure == .normal ? Theme.sage : Theme.coral)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
    }

    private var memoryBand: some View {
        let memory = model.snapshot.memory
        let total = max(1, memory.totalBytes)
        return GeometryReader { geo in
            HStack(spacing: 2) {
                band(memory.appBytes, total, geo.size.width, Theme.lilac)
                band(memory.wiredBytes, total, geo.size.width, Theme.coral)
                band(memory.compressedBytes, total, geo.size.width, Theme.brass)
                band(memory.cachedBytes, total, geo.size.width, Theme.sky)
            }
        }
        .frame(height: 14)
    }

    private func band(_ bytes: Int64, _ total: Int64, _ width: CGFloat, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(color)
            .frame(width: max(0, width * CGFloat(bytes) / CGFloat(total)))
    }

    private func labeled(_ title: String, _ bytes: Int64) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.dim)
            Spacer()
            Text(ByteFormat.string(bytes)).foregroundStyle(Theme.cream).monospacedDigit()
        }
        .font(.system(size: 12))
    }

    private func sparkCard(title: String, keyPath: KeyPath<HistoryPoint, Double>, tint: Color, unit: String) -> some View {
        DeskCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: title)
                Chart(model.history) { point in
                    LineMark(x: .value("Time", point.time), y: .value(title, point[keyPath: keyPath]))
                        .foregroundStyle(tint)
                        .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: 0...1)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 80)
                Text(unit == "%" ? "\(Int((model.snapshot.cpu.usage * 100).rounded()))%" : "")
                    .foregroundStyle(Theme.cream)
            }
        }
    }

    private func rateCard(
        title: String,
        read: Double,
        write: Double,
        readKey: KeyPath<HistoryPoint, Double>,
        writeKey: KeyPath<HistoryPoint, Double>
    ) -> some View {
        DeskCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: title)
                Chart(model.history) { point in
                    LineMark(x: .value("Time", point.time), y: .value("In", point[keyPath: readKey]))
                        .foregroundStyle(Theme.sage)
                    LineMark(x: .value("Time", point.time), y: .value("Out", point[keyPath: writeKey]))
                        .foregroundStyle(Theme.brass)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 80)
                Text("In \(ByteFormat.rate(read)) · Out \(ByteFormat.rate(write))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private func processRow(_ process: ProcessSample) -> some View {
        let denial = ProcessControl.denial(
            name: process.name,
            pid: process.pid,
            uid: process.uid,
            myPid: ProcessInfo.processInfo.processIdentifier,
            myUid: getuid()
        )
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(process.name).foregroundStyle(Theme.cream)
                Text("\(Int(process.cpuPercent.rounded()))% · \(ByteFormat.string(process.memoryBytes))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
            if let denial {
                Text("Protected")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .help(denial)
            } else {
                Button("Pause") { model.control(.pause, pid: process.pid) }.buttonStyle(.plain).foregroundStyle(Theme.brass)
                Button("Resume") { model.control(.resume, pid: process.pid) }.buttonStyle(.plain).foregroundStyle(Theme.sage)
                Button("Low") { model.control(.priorityLow, pid: process.pid) }.buttonStyle(.plain).foregroundStyle(Theme.dim)
                Button("Quit") { model.control(.quit, pid: process.pid) }.buttonStyle(.plain).foregroundStyle(Theme.cream)
                Button("Force") {
                    forceName = process.name
                    forcePID = process.pid
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.coral)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.vertical, 6)
    }

    private func batteryLine(_ battery: BatterySample) -> String {
        var parts: [String] = [battery.charging ? "Charging" : "On battery"]
        if let cycles = battery.cycleCount { parts.append("\(cycles) cycles") }
        if let minutes = battery.timeRemainingMinutes { parts.append("\(minutes) min left") }
        return parts.joined(separator: " · ")
    }
}
