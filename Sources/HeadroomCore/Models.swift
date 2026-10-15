import Foundation

public enum DiskCategory: String, Codable, CaseIterable, Sendable {
    case documentsMedia
    case developerTools
    case codeProjects
    case mobileSDKs
    case aiModels
    case packageCaches
    case osImages
    case systemOther

    public var title: String {
        switch self {
        case .documentsMedia: return "Documents & media"
        case .developerTools: return "Developer tools"
        case .codeProjects: return "Projects"
        case .mobileSDKs: return "Mobile SDKs"
        case .aiModels: return "Models"
        case .packageCaches: return "Package caches"
        case .osImages: return "OS images"
        case .systemOther: return "Everything else"
        }
    }
}

public enum SafetyTier: String, Codable, Sendable {
    case safe
    case review
    case keep

    public var title: String {
        switch self {
        case .safe: return "Safe"
        case .review: return "Review"
        case .keep: return "Keep"
        }
    }
}

public enum RemovalMethod: String, Codable, Sendable, Hashable {
    case trash
    case simctlRuntime
    case simctlUnavailable
    case dockerImage

    public var isPermanent: Bool {
        self == .simctlRuntime || self == .simctlUnavailable || self == .dockerImage
    }
}

public enum BinKind: String, Codable, Sendable, Hashable {
    case cache
    case osImage
    case duplicateFile
    case appBundle
    case appLeftover
}

public enum MenuBarMetric: String, Codable, CaseIterable, Sendable {
    case freeSpace
    case cpu
    case memory
    case combo

    public var title: String {
        switch self {
        case .freeSpace: return "Free space"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .combo: return "CPU and free space"
        }
    }
}

public struct HeadroomSettings: Codable, Equatable, Sendable {
    public var menuBarMetric: MenuBarMetric
    public var showCoresInMenuBar: Bool
    public var freeGigabyteThreshold: Double
    public var freePercentThreshold: Double
    public var cpuThreshold: Double
    public var cpuSustainSeconds: Double
    public var postcardEnabled: Bool
    public var duplicateMinimumMegabytes: Double
    public var hotkeyEnabled: Bool
    public var hotkeyCode: UInt32
    public var hotkeyModifiers: UInt32
    public var stayAwake: Bool
    public var keepDisplayOn: Bool
    public var awakeChoice: AwakeChoice
    public var awakeUntil: Date?

    public init(
        menuBarMetric: MenuBarMetric = .freeSpace,
        showCoresInMenuBar: Bool = true,
        freeGigabyteThreshold: Double = 30,
        freePercentThreshold: Double = 10,
        cpuThreshold: Double = 90,
        cpuSustainSeconds: Double = 120,
        postcardEnabled: Bool = true,
        duplicateMinimumMegabytes: Double = 5,
        hotkeyEnabled: Bool = false,
        hotkeyCode: UInt32 = 0x31,
        hotkeyModifiers: UInt32 = 6144,
        stayAwake: Bool = false,
        keepDisplayOn: Bool = false,
        awakeChoice: AwakeChoice = .untilOff,
        awakeUntil: Date? = nil
    ) {
        self.menuBarMetric = menuBarMetric
        self.showCoresInMenuBar = showCoresInMenuBar
        self.freeGigabyteThreshold = freeGigabyteThreshold
        self.freePercentThreshold = freePercentThreshold
        self.cpuThreshold = cpuThreshold
        self.cpuSustainSeconds = cpuSustainSeconds
        self.postcardEnabled = postcardEnabled
        self.duplicateMinimumMegabytes = duplicateMinimumMegabytes
        self.hotkeyEnabled = hotkeyEnabled
        self.hotkeyCode = hotkeyCode
        self.hotkeyModifiers = hotkeyModifiers
        self.stayAwake = stayAwake
        self.keepDisplayOn = keepDisplayOn
        self.awakeChoice = awakeChoice
        self.awakeUntil = awakeUntil
    }

    public static let standard = HeadroomSettings()
}

public struct CoreSample: Sendable, Identifiable, Equatable {
    public var index: Int
    public var usage: Double
    public var isEfficiency: Bool
    public var id: Int { index }

    public init(index: Int, usage: Double, isEfficiency: Bool) {
        self.index = index
        self.usage = usage
        self.isEfficiency = isEfficiency
    }
}

public struct CPUSample: Sendable, Equatable {
    public var usage: Double
    public var user: Double
    public var system: Double
    public var idle: Double
    public var cores: [CoreSample]

    public init(usage: Double, user: Double, system: Double, idle: Double, cores: [CoreSample]) {
        self.usage = usage
        self.user = user
        self.system = system
        self.idle = idle
        self.cores = cores
    }

    public static let empty = CPUSample(usage: 0, user: 0, system: 0, idle: 1, cores: [])
}

public enum MemoryPressure: String, Sendable, Equatable {
    case normal, warning, urgent, critical

    public var title: String {
        switch self {
        case .normal: return "Calm"
        case .warning: return "Warning"
        case .urgent: return "Urgent"
        case .critical: return "Critical"
        }
    }
}

public struct MemorySample: Sendable, Equatable {
    public var totalBytes: Int64
    public var appBytes: Int64
    public var wiredBytes: Int64
    public var compressedBytes: Int64
    public var cachedBytes: Int64
    public var freeBytes: Int64
    public var pressure: MemoryPressure

    public init(
        totalBytes: Int64,
        appBytes: Int64,
        wiredBytes: Int64,
        compressedBytes: Int64,
        cachedBytes: Int64,
        freeBytes: Int64,
        pressure: MemoryPressure
    ) {
        self.totalBytes = totalBytes
        self.appBytes = appBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.cachedBytes = cachedBytes
        self.freeBytes = freeBytes
        self.pressure = pressure
    }

    public var usedBytes: Int64 { appBytes + wiredBytes + compressedBytes }

    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(usedBytes) / Double(totalBytes))
    }

    public static let empty = MemorySample(
        totalBytes: 0, appBytes: 0, wiredBytes: 0, compressedBytes: 0,
        cachedBytes: 0, freeBytes: 0, pressure: .normal
    )
}

public struct DiskIOSample: Sendable, Equatable {
    public var readBytesPerSecond: Double
    public var writeBytesPerSecond: Double
    public init(readBytesPerSecond: Double = 0, writeBytesPerSecond: Double = 0) {
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
    }
}

public struct NetworkSample: Sendable, Equatable {
    public var inBytesPerSecond: Double
    public var outBytesPerSecond: Double
    public init(inBytesPerSecond: Double = 0, outBytesPerSecond: Double = 0) {
        self.inBytesPerSecond = inBytesPerSecond
        self.outBytesPerSecond = outBytesPerSecond
    }
}

public struct BatterySample: Sendable, Equatable {
    public var percent: Double
    public var charging: Bool
    public var cycleCount: Int?
    public var timeRemainingMinutes: Int?

    public init(percent: Double, charging: Bool, cycleCount: Int?, timeRemainingMinutes: Int?) {
        self.percent = percent
        self.charging = charging
        self.cycleCount = cycleCount
        self.timeRemainingMinutes = timeRemainingMinutes
    }
}

public enum ThermalLevel: String, Sendable, Equatable {
    case nominal, fair, serious, critical

    public var title: String {
        switch self {
        case .nominal: return "Cool"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        }
    }
}

public struct ProcessSample: Sendable, Identifiable, Equatable {
    public var pid: Int32
    public var name: String
    public var cpuPercent: Double
    public var memoryBytes: Int64
    public var nice: Int
    public var uid: UInt32
    public var id: Int32 { pid }

    public init(pid: Int32, name: String, cpuPercent: Double, memoryBytes: Int64, nice: Int, uid: UInt32) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.nice = nice
        self.uid = uid
    }
}

public struct VolumeInfo: Sendable, Identifiable, Equatable {
    public var name: String
    public var path: String
    public var totalBytes: Int64
    public var freeBytes: Int64
    public var availableBytes: Int64
    public var isInternal: Bool
    public var id: String { path }

    public init(name: String, path: String, totalBytes: Int64, freeBytes: Int64, availableBytes: Int64, isInternal: Bool) {
        self.name = name
        self.path = path
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.availableBytes = availableBytes
        self.isInternal = isInternal
    }

    /// Finder's "available" includes space the system can purge. This is that extra.
    public var purgeableBytes: Int64 { max(0, availableBytes - freeBytes) }

    public var usedBytes: Int64 { max(0, totalBytes - freeBytes) }

    public var freeFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(freeBytes) / Double(totalBytes))
    }
}

public struct SystemSnapshot: Sendable, Equatable {
    public var capturedAt: Date
    public var cpu: CPUSample
    public var memory: MemorySample
    public var diskIO: DiskIOSample
    public var network: NetworkSample
    public var thermal: ThermalLevel
    public var battery: BatterySample?
    public var processes: [ProcessSample]
    public var volumes: [VolumeInfo]
    public var uptime: TimeInterval

    public init(
        capturedAt: Date,
        cpu: CPUSample,
        memory: MemorySample,
        diskIO: DiskIOSample,
        network: NetworkSample,
        thermal: ThermalLevel,
        battery: BatterySample?,
        processes: [ProcessSample],
        volumes: [VolumeInfo],
        uptime: TimeInterval
    ) {
        self.capturedAt = capturedAt
        self.cpu = cpu
        self.memory = memory
        self.diskIO = diskIO
        self.network = network
        self.thermal = thermal
        self.battery = battery
        self.processes = processes
        self.volumes = volumes
        self.uptime = uptime
    }

    public static let empty = SystemSnapshot(
        capturedAt: .distantPast,
        cpu: .empty,
        memory: .empty,
        diskIO: DiskIOSample(),
        network: NetworkSample(),
        thermal: .nominal,
        battery: nil,
        processes: [],
        volumes: [],
        uptime: 0
    )

    public var primaryVolume: VolumeInfo? {
        volumes.first(where: \.isInternal) ?? volumes.first
    }
}

public struct HistoryPoint: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var time: Date
    public var cpu: Double
    public var memory: Double
    public var diskRead: Double
    public var diskWrite: Double
    public var netIn: Double
    public var netOut: Double

    public init(
        id: UUID = UUID(),
        time: Date,
        cpu: Double,
        memory: Double,
        diskRead: Double,
        diskWrite: Double,
        netIn: Double,
        netOut: Double
    ) {
        self.id = id
        self.time = time
        self.cpu = cpu
        self.memory = memory
        self.diskRead = diskRead
        self.diskWrite = diskWrite
        self.netIn = netIn
        self.netOut = netOut
    }
}

public struct FileNode: Codable, Sendable, Identifiable, Equatable {
    public var name: String
    public var path: String
    public var allocatedBytes: Int64
    public var isDirectory: Bool
    public var children: [FileNode]
    public var partial: Bool
    public var containsGit: Bool
    public var id: String { path }

    public init(
        name: String,
        path: String,
        allocatedBytes: Int64,
        isDirectory: Bool,
        children: [FileNode] = [],
        partial: Bool = false,
        containsGit: Bool = false
    ) {
        self.name = name
        self.path = path
        self.allocatedBytes = allocatedBytes
        self.isDirectory = isDirectory
        self.children = children
        self.partial = partial
        self.containsGit = containsGit
    }
}

public struct CleanupCandidate: Codable, Sendable, Identifiable, Hashable, Equatable {
    public var path: String
    public var bytes: Int64
    public var title: String
    public var detail: String
    public var tier: SafetyTier
    public var category: DiskCategory
    public var ruleID: String
    public var id: String { path }

    public init(
        path: String,
        bytes: Int64,
        title: String,
        detail: String,
        tier: SafetyTier,
        category: DiskCategory,
        ruleID: String
    ) {
        self.path = path
        self.bytes = bytes
        self.title = title
        self.detail = detail
        self.tier = tier
        self.category = category
        self.ruleID = ruleID
    }

    public func binItem() -> BinItem {
        BinItem(
            id: "cache:" + path,
            title: title,
            subtitle: path,
            bytes: bytes,
            method: .trash,
            kind: .cache,
            payload: path,
            expectedHash: nil,
            bundleID: nil
        )
    }
}

public struct ScanResult: Codable, Sendable, Equatable {
    public var root: String
    public var scannedAt: Date
    public var tree: FileNode
    public var candidates: [CleanupCandidate]
    public var partial: Bool

    public init(root: String, scannedAt: Date, tree: FileNode, candidates: [CleanupCandidate], partial: Bool) {
        self.root = root
        self.scannedAt = scannedAt
        self.tree = tree
        self.candidates = candidates
        self.partial = partial
    }

    public var safeBytes: Int64 {
        candidates.filter { $0.tier == .safe }.reduce(0) { $0 + $1.bytes }
    }

    public var reviewBytes: Int64 {
        candidates.filter { $0.tier == .review }.reduce(0) { $0 + $1.bytes }
    }
}

public struct PathDelta: Sendable, Identifiable, Equatable {
    public var path: String
    public var name: String
    public var bytes: Int64
    public var id: String { path }

    public init(path: String, name: String, bytes: Int64) {
        self.path = path
        self.name = name
        self.bytes = bytes
    }
}

public enum OSImageKind: String, Sendable, Equatable {
    case appleSimulator
    case appleDevices
    case androidSystem
    case docker
    case macInstaller

    public var title: String {
        switch self {
        case .appleSimulator: return "Simulator"
        case .appleDevices: return "Simulators"
        case .androidSystem: return "Android"
        case .docker: return "Docker"
        case .macInstaller: return "macOS installer"
        }
    }
}

public struct OSImageItem: Sendable, Identifiable, Hashable, Equatable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var bytes: Int64
    public var kind: OSImageKind
    public var method: RemovalMethod
    public var payload: String

    public init(id: String, title: String, subtitle: String, bytes: Int64, kind: OSImageKind, method: RemovalMethod, payload: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.bytes = bytes
        self.kind = kind
        self.method = method
        self.payload = payload
    }

    public func binItem() -> BinItem {
        BinItem(
            id: "image:" + id,
            title: title,
            subtitle: subtitle,
            bytes: bytes,
            method: method,
            kind: .osImage,
            payload: payload,
            expectedHash: nil,
            bundleID: nil
        )
    }
}

public struct OSImageReport: Sendable, Equatable {
    public var items: [OSImageItem]
    public var notes: [String]

    public init(items: [OSImageItem], notes: [String]) {
        self.items = items
        self.notes = notes
    }
}

public struct Leftover: Sendable, Identifiable, Hashable, Equatable {
    public var path: String
    public var bytes: Int64
    public var kind: String
    public var id: String { path }

    public init(path: String, bytes: Int64, kind: String) {
        self.path = path
        self.bytes = bytes
        self.kind = kind
    }
}

public struct InstalledApp: Sendable, Identifiable, Equatable {
    public var name: String
    public var bundleID: String
    public var path: String
    public var bytes: Int64
    public var leftovers: [Leftover]
    public var id: String { bundleID + "|" + path }

    public init(name: String, bundleID: String, path: String, bytes: Int64, leftovers: [Leftover]) {
        self.name = name
        self.bundleID = bundleID
        self.path = path
        self.bytes = bytes
        self.leftovers = leftovers
    }
}

public struct CloudPlace: Sendable, Identifiable, Equatable {
    public var provider: String
    public var path: String
    public var localBytes: Int64?
    public var note: String
    public var id: String { path }

    public init(provider: String, path: String, localBytes: Int64?, note: String) {
        self.provider = provider
        self.path = path
        self.localBytes = localBytes
        self.note = note
    }
}

public struct BinItem: Sendable, Identifiable, Hashable, Equatable, Codable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var bytes: Int64
    public var method: RemovalMethod
    public var kind: BinKind
    public var payload: String
    public var expectedHash: String?
    public var bundleID: String?

    public init(
        id: String,
        title: String,
        subtitle: String,
        bytes: Int64,
        method: RemovalMethod,
        kind: BinKind,
        payload: String,
        expectedHash: String?,
        bundleID: String?
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.bytes = bytes
        self.method = method
        self.kind = kind
        self.payload = payload
        self.expectedHash = expectedHash
        self.bundleID = bundleID
    }
}

public struct RemovalOutcome: Sendable, Identifiable, Equatable {
    public var title: String
    public var payload: String
    public var ok: Bool
    public var message: String
    public var id: String { payload + title }

    public init(title: String, payload: String, ok: Bool, message: String) {
        self.title = title
        self.payload = payload
        self.ok = ok
        self.message = message
    }
}

public struct CleanupLogEntry: Codable, Sendable, Equatable {
    public var date: Date
    public var bytes: Int64
    public var titles: [String]

    public init(date: Date, bytes: Int64, titles: [String]) {
        self.date = date
        self.bytes = bytes
        self.titles = titles
    }
}

public enum Preset: String, CaseIterable, Sendable, Identifiable {
    case xcodeHaircut
    case nodeDiet
    case modelCloset
    case dockerDryDock

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .xcodeHaircut: return "Xcode haircut"
        case .nodeDiet: return "Node diet"
        case .modelCloset: return "Model closet"
        case .dockerDryDock: return "Docker dry dock"
        }
    }

    public var blurb: String {
        switch self {
        case .xcodeHaircut: return "DerivedData, indexes, and old device support"
        case .nodeDiet: return "Package caches and build output"
        case .modelCloset: return "Local model folders you can redownload"
        case .dockerDryDock: return "Images Docker can pull again"
        }
    }

    public var ruleIDs: Set<String> {
        switch self {
        case .xcodeHaircut:
            return ["xcode.derived", "xcode.cache", "sim.caches", "xcode.devicesupport", "xcode.archives"]
        case .nodeDiet:
            return ["node.modules", "npm.cache", "pnpm.store", "yarn.cache", "next.build", "turbo.cache"]
        case .modelCloset:
            return ["ollama", "ollama.support", "huggingface", "lmstudio"]
        case .dockerDryDock:
            return []
        }
    }
}

public enum AlertKind: String, Sendable, Codable, Equatable {
    case disk, memory, cpu, thermal, newJunk, postcard
}

public struct Alert: Sendable, Identifiable, Equatable {
    public var kind: AlertKind
    public var title: String
    public var body: String
    public var id: String { kind.rawValue }

    public init(kind: AlertKind, title: String, body: String) {
        self.kind = kind
        self.title = title
        self.body = body
    }
}

public struct AlertState: Sendable, Equatable {
    public var cpuHighSince: Date?
    public var lastNotified: [String: Date]

    public init(cpuHighSince: Date? = nil, lastNotified: [String: Date] = [:]) {
        self.cpuHighSince = cpuHighSince
        self.lastNotified = lastNotified
    }
}

public struct WalkProgress: Sendable, Equatable {
    public var currentPath: String
    public var visitedDirectories: Int

    public init(currentPath: String, visitedDirectories: Int) {
        self.currentPath = currentPath
        self.visitedDirectories = visitedDirectories
    }

    public var label: String {
        let name = (currentPath as NSString).lastPathComponent
        return "Mapping \(name.isEmpty ? currentPath : name) · \(visitedDirectories) folders"
    }
}

public enum ProcessAction: String, Sendable {
    case quit
    case forceQuit
    case pause
    case resume
    case priorityLow
    case priorityNormal

    public var title: String {
        switch self {
        case .quit: return "Quit"
        case .forceQuit: return "Force quit"
        case .pause: return "Pause"
        case .resume: return "Resume"
        case .priorityLow: return "Low priority"
        case .priorityNormal: return "Normal priority"
        }
    }
}

public struct ProcessControlResult: Sendable, Equatable {
    public var ok: Bool
    public var message: String
    public init(ok: Bool, message: String) {
        self.ok = ok
        self.message = message
    }
}

public struct DuplicateFile: Sendable, Hashable, Identifiable, Equatable {
    public var path: String
    public var bytes: Int64
    public var modified: Date
    public var id: String { path }

    public init(path: String, bytes: Int64, modified: Date) {
        self.path = path
        self.bytes = bytes
        self.modified = modified
    }
}

public struct DuplicateGroup: Sendable, Identifiable, Equatable {
    public var hash: String
    public var files: [DuplicateFile]
    public var id: String { hash }

    public init(hash: String, files: [DuplicateFile]) {
        self.hash = hash
        self.files = files
    }

    public var wastedBytes: Int64 {
        guard let first = files.first, files.count > 1 else { return 0 }
        return first.bytes * Int64(files.count - 1)
    }
}

public enum KeepPolicy: String, Sendable {
    case newest
    case oldest
}

public struct Postcard: Sendable, Equatable {
    public var title: String
    public var lines: [String]
    public init(title: String, lines: [String]) {
        self.title = title
        self.lines = lines
    }
}

public struct LayoutRect: Equatable, Sendable, Identifiable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var path: String
    public var name: String
    public var bytes: Int64
    public var depth: Int
    public var id: String { path + ":\(depth)" }

    public init(x: Double, y: Double, width: Double, height: Double, path: String, name: String, bytes: Int64, depth: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.path = path
        self.name = name
        self.bytes = bytes
        self.depth = depth
    }
}
