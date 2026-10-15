import Darwin
import Foundation
import IOKit
import IOKit.ps

/// Samples CPU, memory, disk, network, thermals, battery, and processes.
/// `pti_total_user` / `pti_total_system` are nanoseconds on this OS.
public final class SystemSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var previousTicks: [(user: Int64, system: Int64, idle: Int64, nice: Int64)] = []
    private var previousNetIn: UInt64 = 0
    private var previousNetOut: UInt64 = 0
    private var previousNetTime: Date?
    private var previousDiskRead: UInt64 = 0
    private var previousDiskWrite: UInt64 = 0
    private var previousDiskTime: Date?
    private var previousProcessTime: [Int32: (nanoseconds: UInt64, at: Date)] = [:]
    private let performanceCoreCount: Int

    public init() {
        var perf: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.logicalcpu", &perf, &size, nil, 0) == 0, perf > 0 {
            performanceCoreCount = Int(perf)
        } else {
            performanceCoreCount = 0
        }
    }

    public func sample() -> SystemSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        let cpu = cpuSample()
        let memory = memorySample()
        let disk = diskSample(now: now)
        let network = networkSample(now: now)
        let processes = processSample(now: now)
        return SystemSnapshot(
            capturedAt: now,
            cpu: cpu,
            memory: memory,
            diskIO: disk,
            network: network,
            thermal: thermal(),
            battery: battery(),
            processes: processes,
            volumes: VolumeCatalog.current(),
            uptime: ProcessInfo.processInfo.systemUptime
        )
    }

    private func cpuSample() -> CPUSample {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return .empty }
        defer {
            let bytes = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), bytes)
        }
        let states = Int(CPU_STATE_MAX)
        var ticks: [(user: Int64, system: Int64, idle: Int64, nice: Int64)] = []
        ticks.reserveCapacity(Int(cpuCount))
        for index in 0..<Int(cpuCount) {
            let base = index * states
            ticks.append((
                user: Int64(info[base + Int(CPU_STATE_USER)]),
                system: Int64(info[base + Int(CPU_STATE_SYSTEM)]),
                idle: Int64(info[base + Int(CPU_STATE_IDLE)]),
                nice: Int64(info[base + Int(CPU_STATE_NICE)])
            ))
        }
        let previous = previousTicks
        previousTicks = ticks
        guard previous.count == ticks.count else { return .empty }
        var cores: [CoreSample] = []
        var userDelta: Int64 = 0
        var systemDelta: Int64 = 0
        var idleDelta: Int64 = 0
        var niceDelta: Int64 = 0
        for index in ticks.indices {
            let du = ticks[index].user - previous[index].user
            let ds = ticks[index].system - previous[index].system
            let di = ticks[index].idle - previous[index].idle
            let dn = ticks[index].nice - previous[index].nice
            let total = max(1, du + ds + di + dn)
            let usage = Double(du + ds + dn) / Double(total)
            userDelta += du
            systemDelta += ds
            idleDelta += di
            niceDelta += dn
            let efficiency = performanceCoreCount > 0 && index >= performanceCoreCount
            cores.append(CoreSample(index: index, usage: min(1, max(0, usage)), isEfficiency: efficiency))
        }
        let all = max(1, userDelta + systemDelta + idleDelta + niceDelta)
        return CPUSample(
            usage: Double(userDelta + systemDelta + niceDelta) / Double(all),
            user: Double(userDelta) / Double(all),
            system: Double(systemDelta + niceDelta) / Double(all),
            idle: Double(idleDelta) / Double(all),
            cores: cores
        )
    }

    private func memorySample() -> MemorySample {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPointer, &count)
            }
        }
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        guard result == KERN_SUCCESS else {
            return MemorySample(totalBytes: total, appBytes: 0, wiredBytes: 0, compressedBytes: 0, cachedBytes: 0, freeBytes: 0, pressure: pressureLevel())
        }
        let page = Int64(vm_kernel_page_size)
        let app = max(0, (Int64(stats.internal_page_count) - Int64(stats.purgeable_count)) * page)
        let wired = Int64(stats.wire_count) * page
        let compressed = Int64(stats.compressor_page_count) * page
        let cached = (Int64(stats.external_page_count) + Int64(stats.purgeable_count)) * page
        let free = Int64(stats.free_count) * page
        return MemorySample(
            totalBytes: total,
            appBytes: app,
            wiredBytes: wired,
            compressedBytes: compressed,
            cachedBytes: cached,
            freeBytes: free,
            pressure: pressureLevel()
        )
    }

    private func pressureLevel() -> MemoryPressure {
        var level: UInt32 = 0
        var size = MemoryLayout<UInt32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .normal
        }
        if level >= 8 { return .critical }
        if level >= 4 { return .urgent }
        if level >= 2 { return .warning }
        return .normal
    }

    private func diskSample(now: Date) -> DiskIOSample {
        let totals = diskTotals()
        defer {
            previousDiskRead = totals.read
            previousDiskWrite = totals.write
            previousDiskTime = now
        }
        guard let then = previousDiskTime else { return DiskIOSample() }
        let seconds = now.timeIntervalSince(then)
        guard seconds > 0.2 else { return DiskIOSample() }
        let read = rate(delta(totals.read, previousDiskRead), seconds: seconds)
        let write = rate(delta(totals.write, previousDiskWrite), seconds: seconds)
        return DiskIOSample(readBytesPerSecond: read, writeBytesPerSecond: write)
    }

    private func diskTotals() -> (read: UInt64, write: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0
        var write: UInt64 = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let property = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0) else {
                continue
            }
            let value = property.takeRetainedValue()
            guard let stats = value as? [String: Any], let bytes = stats["Bytes"] as? [String: Any] else { continue }
            if let number = bytes["read"] as? NSNumber { read += number.uint64Value }
            if let number = bytes["write"] as? NSNumber { write += number.uint64Value }
        }
        return (read, write)
    }

    private func networkSample(now: Date) -> NetworkSample {
        let totals = networkTotals()
        defer {
            previousNetIn = totals.inn
            previousNetOut = totals.out
            previousNetTime = now
        }
        guard let then = previousNetTime else { return NetworkSample() }
        let seconds = now.timeIntervalSince(then)
        guard seconds > 0.2 else { return NetworkSample() }
        return NetworkSample(
            inBytesPerSecond: rate(delta(totals.inn, previousNetIn), seconds: seconds),
            outBytesPerSecond: rate(delta(totals.out, previousNetOut), seconds: seconds)
        )
    }

    private func networkTotals() -> (inn: UInt64, out: UInt64) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return (0, 0) }
        defer { freeifaddrs(first) }
        var inbound: UInt64 = 0
        var outbound: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = cursor {
            let name = String(cString: interface.pointee.ifa_name)
            if name != "lo0", let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
               let data = interface.pointee.ifa_data {
                let stats = data.assumingMemoryBound(to: if_data.self)
                inbound += UInt64(stats.pointee.ifi_ibytes)
                outbound += UInt64(stats.pointee.ifi_obytes)
            }
            cursor = interface.pointee.ifa_next
        }
        return (inbound, outbound)
    }

    private func delta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        if current >= previous { return current - previous }
        if previous <= UInt64(UInt32.max) {
            return (UInt64(UInt32.max) - previous + 1) + current
        }
        return 0
    }

    private func rate(_ bytes: UInt64, seconds: TimeInterval) -> Double {
        let value = Double(bytes) / seconds
        if value < 0 || value > 100_000_000_000 { return 0 }
        return value
    }

    private func processSample(now: Date) -> [ProcessSample] {
        let byteCount = proc_listallpids(nil, 0)
        let capacity = max(32, Int(byteCount) / MemoryLayout<pid_t>.size + 32)
        var pids = [pid_t](repeating: 0, count: capacity)
        let written = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let count = max(0, min(pids.count, Int(written) / MemoryLayout<pid_t>.size))
        var measured: [(pid: Int32, cpu: Double, memory: Int64, time: UInt64)] = []
        var nextTimes: [Int32: (nanoseconds: UInt64, at: Date)] = [:]
        for index in 0..<count {
            let pid = pids[index]
            if pid <= 0 { continue }
            var info = proc_taskinfo()
            let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
            guard size == Int32(MemoryLayout<proc_taskinfo>.size) else { continue }
            let time = info.pti_total_user &+ info.pti_total_system
            nextTimes[pid] = (time, now)
            var cpu = 0.0
            if let previous = previousProcessTime[pid] {
                let elapsed = now.timeIntervalSince(previous.at)
                if elapsed > 0.2 {
                    let spent = Double(time &- previous.nanoseconds) / 1_000_000_000
                    cpu = min(100 * Double(max(1, ProcessInfo.processInfo.activeProcessorCount)), max(0, spent / elapsed * 100))
                }
            }
            measured.append((pid, cpu, Int64(info.pti_resident_size), time))
        }
        previousProcessTime = nextTimes
        let byCPU = measured.sorted { lhs, rhs in
            if lhs.cpu == rhs.cpu { return lhs.memory > rhs.memory }
            return lhs.cpu > rhs.cpu
        }
        let byMemory = measured.sorted { $0.memory > $1.memory }
        var seen = Set<Int32>()
        var ranked: [(pid: Int32, cpu: Double, memory: Int64, time: UInt64)] = []
        for item in byCPU.prefix(16) where seen.insert(item.pid).inserted {
            ranked.append(item)
        }
        for item in byMemory.prefix(12) where seen.insert(item.pid).inserted {
            ranked.append(item)
        }
        return ranked.map { item in
            var nameBuffer = [CChar](repeating: 0, count: 256)
            let length = proc_name(item.pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = length > 0 ? String(cString: nameBuffer) : "pid \(item.pid)"
            var bsd = proc_bsdinfo()
            let bsdSize = proc_pidinfo(item.pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.size))
            let uid: UInt32 = bsdSize == Int32(MemoryLayout<proc_bsdinfo>.size) ? bsd.pbi_uid : UInt32.max
            errno = 0
            let nice = getpriority(PRIO_PROCESS, id_t(item.pid))
            return ProcessSample(
                pid: item.pid,
                name: name,
                cpuPercent: item.cpu,
                memoryBytes: item.memory,
                nice: Int(nice),
                uid: uid
            )
        }
    }

    private func thermal() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }

    private func battery() -> BatterySample? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        guard let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(blob, item)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? -1
            let max = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 0
            guard max > 0, current >= 0 else { continue }
            let charging = (description[kIOPSIsChargingKey] as? NSNumber)?.boolValue ?? false
            let minutes = (description[kIOPSTimeToEmptyKey] as? NSNumber)?.intValue
            let cycles = (description["Cycle Count"] as? NSNumber)?.intValue
            let remaining = (minutes ?? 0) > 0 ? minutes : nil
            return BatterySample(
                percent: min(1, current / max),
                charging: charging,
                cycleCount: cycles,
                timeRemainingMinutes: remaining
            )
        }
        return nil
    }
}
