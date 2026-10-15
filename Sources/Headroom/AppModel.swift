import AppKit
import Foundation
import HeadroomCore
import Observation
import ServiceManagement

enum SettingsStore {
    static let key = "headroom.settings.v1"
    static let postcardKey = "headroom.postcard.last"

    static func load() -> HeadroomSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(HeadroomSettings.self, from: data) else {
            return .standard
        }
        return settings
    }

    static func save(_ settings: HeadroomSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static var lastPostcard: Date? {
        get { UserDefaults.standard.object(forKey: postcardKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: postcardKey) }
    }
}

@MainActor
@Observable
final class AppModel {
    var snapshot = SystemSnapshot.empty
    var history: [HistoryPoint] = []
    var settings = HeadroomSettings.standard
    var activeAlerts: [Alert] = []
    var scan: ScanResult?
    var previousScan: ScanResult?
    var scanning = false
    var scanProgress = ""
    var bin: [BinItem] = []
    var page: DeskPage = .overview
    var imageReport = OSImageReport(items: [], notes: [])
    var loadingImages = false
    var includeDocker = false
    var apps: [InstalledApp] = []
    var loadingApps = false
    var clouds: [CloudPlace] = []
    var measuringCloud = false
    var duplicateGroups: [DuplicateGroup] = []
    var duplicateProgress = ""
    var scanningDuplicates = false
    var outcomes: [RemovalOutcome] = []
    var showConfirm = false
    var showResults = false
    var acceptPermanent = false
    var removing = false
    var banner: String?
    var loginError: String?
    var alertsAllowed = false
    var hotkeyPulse = 0
    var launchAtLogin = false

    @ObservationIgnored private let sampler = SystemSampler()
    @ObservationIgnored private let notifier = Notifier()
    @ObservationIgnored private let hotkeys = HotkeyCenter()
    @ObservationIgnored private var sampleTask: Task<Void, Never>?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var alertState = AlertState()
    @ObservationIgnored private var didAskForDesk = false
    @ObservationIgnored var deskWindow: NSWindow?

    init() {
        settings = SettingsStore.load()
        let home = NSHomeDirectory()
        scan = ScanStore.loadLatest(root: home)
        previousScan = ScanStore.loadPrevious(root: home)
        notifier.start()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        hotkeys.onPress = { [weak self] in
            Task { @MainActor in self?.hotkeyPulse += 1 }
        }
        applyHotkey()
        startSampling()
        refreshAlertAuthorization()
        observeWindows()
        clouds = CloudFootprint.places(home: home)
        if CommandLine.arguments.contains("--desk") {
            didAskForDesk = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                self.presentDesk()
            }
        }
    }

    func presentDesk() {
        DeskWindow.present(model: self)
    }

    var menuLabel: String {
        guard let volume = snapshot.primaryVolume else { return "…" }
        switch settings.menuBarMetric {
        case .freeSpace:
            return ByteFormat.string(volume.freeBytes)
        case .cpu:
            return "\(Int((snapshot.cpu.usage * 100).rounded()))%"
        case .memory:
            return "\(Int((snapshot.memory.usedFraction * 100).rounded()))%"
        case .combo:
            return "\(Int((snapshot.cpu.usage * 100).rounded()))%  \(ByteFormat.string(volume.freeBytes))"
        }
    }

    var hasAlert: Bool { !activeAlerts.isEmpty }

    var reviewBytes: Int64 { (scan?.safeBytes ?? 0) + (scan?.reviewBytes ?? 0) }

    var binBytes: Int64 { bin.reduce(0) { $0 + $1.bytes } }

    var permanentInBin: Bool { bin.contains { $0.method.isPermanent } }

    func consumeLaunchRequest() -> Bool {
        guard !didAskForDesk else { return false }
        didAskForDesk = true
        return CommandLine.arguments.contains("--desk")
    }

    func prepareDesk() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateSettings(_ mutate: (inout HeadroomSettings) -> Void) {
        mutate(&settings)
        SettingsStore.save(settings)
        applyHotkey()
    }

    func allowAlerts() {
        notifier.request()
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            refreshAlertAuthorization()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = error.localizedDescription
        }
    }

    func scanHome() {
        scan(root: FileManager.default.homeDirectoryForCurrentUser)
    }

    func chooseScanFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Headroom only reads this folder. It does not delete anything while mapping."
        panel.prompt = "Map"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scan(root: url)
    }

    func scan(root: URL) {
        let path = root.standardizedFileURL.path
        let blocked = ["/", "/System", "/usr", "/private", "/Library", "/bin", "/sbin", "/dev"]
        if blocked.contains(path) {
            banner = "Pick a folder on a disk. The system root stays unmapped."
            return
        }
        scanTask?.cancel()
        scanning = true
        scanProgress = "Starting in \(PathDisplay.shortName(root.path, fallback: root.lastPathComponent))"
        let home = NSHomeDirectory()
        scanTask = Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .utility) {
                    try DirectoryWalker.scan(root: root, home: home) { progress in
                        Task { @MainActor in
                            self?.scanProgress = progress.label
                        }
                    }
                }.value
                self?.finishScan(result)
            } catch is CancellationError {
                self?.scanning = false
                self?.scanProgress = "Mapping cancelled"
            } catch {
                self?.scanning = false
                self?.scanProgress = error.localizedDescription
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func add(_ item: BinItem) {
        guard !bin.contains(where: { $0.id == item.id }) else { return }
        bin.append(item)
        banner = "Added \(item.title) to the bin. Nothing is removed yet."
    }

    func removeFromBin(_ id: String) {
        bin.removeAll { $0.id == id }
    }

    func addPreset(_ preset: Preset) {
        if preset == .dockerDryDock {
            let docker = imageReport.items.filter { $0.kind == .docker }
            docker.forEach { add($0.binItem()) }
            if docker.isEmpty {
                banner = "Look at Docker first. Nothing was added."
            }
            return
        }
        guard let scan else {
            banner = "Map a folder before using a preset."
            return
        }
        let matches = scan.candidates.filter { preset.ruleIDs.contains($0.ruleID) }
        matches.forEach { add($0.binItem()) }
        banner = matches.isEmpty ? "No \(preset.title.lowercased()) items in this map." : "Staged \(matches.count) items. The bin still waits for you."
    }

    func stageDuplicates(_ group: DuplicateGroup, keeping path: String) {
        for file in DuplicateGrouper.extras(in: group, keeping: path) {
            add(BinItem(
                id: "dup:" + file.path,
                title: (file.path as NSString).lastPathComponent,
                subtitle: PathDisplay.string(file.path),
                bytes: file.bytes,
                method: .trash,
                kind: .duplicateFile,
                payload: file.path,
                expectedHash: group.hash,
                bundleID: nil
            ))
        }
    }

    func stageApp(_ app: InstalledApp, leftoverPaths: Set<String>) {
        add(BinItem(
            id: "app:" + app.path,
            title: app.name,
            subtitle: PathDisplay.string(app.path),
            bytes: app.bytes,
            method: .trash,
            kind: .appBundle,
            payload: app.path,
            expectedHash: nil,
            bundleID: app.bundleID
        ))
        for leftover in app.leftovers where leftoverPaths.contains(leftover.path) {
            add(BinItem(
                id: "left:" + leftover.path,
                title: leftover.kind,
                subtitle: PathDisplay.string(leftover.path),
                bytes: leftover.bytes,
                method: .trash,
                kind: .appLeftover,
                payload: leftover.path,
                expectedHash: nil,
                bundleID: app.bundleID
            ))
        }
    }

    func exportScript() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Headroom-cleanup.zsh"
        panel.prompt = "Export"
        panel.message = "The script moves files to the Trash after you type DELETE."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let script = CleanupPlan.script(bin, home: NSHomeDirectory())
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            banner = "Exported a script. It does not run until you run it."
        } catch {
            banner = error.localizedDescription
        }
    }

    func removeConfirmed() {
        guard !bin.isEmpty, !removing else { return }
        if permanentInBin && !acceptPermanent { return }
        removing = true
        let items = bin
        let home = NSHomeDirectory()
        Task.detached(priority: .utility) { [weak self] in
            let outcomes = CleanupRunner.perform(items, home: home)
            let model = self
            await MainActor.run {
                model?.apply(outcomes: outcomes, items: items)
            }
        }
    }

    func loadImages() {
        loadingImages = true
        let home = NSHomeDirectory()
        let docker = includeDocker
        Task.detached(priority: .utility) { [weak self] in
            let report = OSImageScanner.scan(home: home, includeDocker: docker)
            let model = self
            await MainActor.run {
                model?.imageReport = report
                model?.loadingImages = false
            }
        }
    }

    func loadApps() {
        loadingApps = true
        let home = NSHomeDirectory()
        Task.detached(priority: .utility) { [weak self] in
            let apps = AppInventory.load(home: home)
            let model = self
            await MainActor.run {
                model?.apps = apps
                model?.loadingApps = false
            }
        }
    }

    func measureClouds() {
        measuringCloud = true
        let places = clouds
        Task.detached(priority: .utility) { [weak self] in
            let measured = places.map { CloudFootprint.measure($0) }
            let model = self
            await MainActor.run {
                model?.clouds = measured
                model?.measuringCloud = false
            }
        }
    }

    func chooseDuplicateFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Only these folders are hashed. iCloud placeholders are skipped."
        panel.prompt = "Find duplicates"
        guard panel.runModal() == .OK else { return }
        findDuplicates(panel.urls)
    }

    func findDuplicates(_ roots: [URL]) {
        scanningDuplicates = true
        duplicateProgress = "Starting"
        let minimum = Int64(settings.duplicateMinimumMegabytes * 1_000_000)
        Task { [weak self] in
            do {
                let groups = try await Task.detached(priority: .utility) {
                    try DuplicateScanner.find(roots: roots, minimumBytes: minimum) { progress in
                        Task { @MainActor in self?.duplicateProgress = progress.label }
                    }
                }.value
                self?.duplicateGroups = groups
                self?.scanningDuplicates = false
                self?.duplicateProgress = groups.isEmpty ? "No duplicates in those folders." : "\(groups.count) groups"
            } catch is CancellationError {
                self?.scanningDuplicates = false
            } catch {
                self?.scanningDuplicates = false
                self?.duplicateProgress = error.localizedDescription
            }
        }
    }

    func control(_ action: ProcessAction, pid: Int32) {
        let result = ProcessControl.perform(action, pid: pid)
        banner = result.message
    }

    func openPrivacySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }

    private func startSampling() {
        let sampler = sampler
        sampleTask = Task { [weak self] in
            while !Task.isCancelled {
                let snapshot = await Task.detached(priority: .utility) { sampler.sample() }.value
                self?.ingest(snapshot)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func ingest(_ snapshot: SystemSnapshot) {
        self.snapshot = snapshot
        history.append(HistoryPoint(
            time: snapshot.capturedAt,
            cpu: snapshot.cpu.usage,
            memory: snapshot.memory.usedFraction,
            diskRead: snapshot.diskIO.readBytesPerSecond,
            diskWrite: snapshot.diskIO.writeBytesPerSecond,
            netIn: snapshot.network.inBytesPerSecond,
            netOut: snapshot.network.outBytesPerSecond
        ))
        if history.count > 900 {
            history.removeFirst(history.count - 900)
        }
        let evaluation = AlertEngine.evaluate(
            snapshot: snapshot,
            settings: settings,
            state: alertState,
            newlyReviewableBytes: newlyReviewable(),
            now: Date()
        )
        alertState = evaluation.state
        activeAlerts = evaluation.active
        guard alertsAllowed else { return }
        for alert in evaluation.notify {
            notifier.post(alert)
        }
        maybePostcard()
    }

    private func newlyReviewable() -> Int64 {
        guard let scan, let previousScan, scan.root == previousScan.root else { return 0 }
        let current = scan.safeBytes + scan.reviewBytes
        let previous = previousScan.safeBytes + previousScan.reviewBytes
        return max(0, current - previous)
    }

    private func maybePostcard() {
        let now = Date()
        guard PostcardMaker.shouldSend(now: now, lastSent: SettingsStore.lastPostcard, enabled: settings.postcardEnabled) else {
            return
        }
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let card = PostcardMaker.make(
            now: now,
            lastScan: scan,
            previous: previousScan,
            freedThisWeek: ScanStore.freed(since: weekAgo)
        )
        notifier.post(Alert(kind: .postcard, title: card.title, body: card.lines.joined(separator: " ")))
        SettingsStore.lastPostcard = now
    }

    private func finishScan(_ result: ScanResult) {
        scanning = false
        scan = result
        scanProgress = "Mapped \(ByteFormat.string(result.tree.allocatedBytes))"
        do {
            try ScanStore.save(result)
            previousScan = ScanStore.loadPrevious(root: result.root)
        } catch {
            banner = "The map is ready, and saving a copy of it failed."
        }
    }

    private func apply(outcomes: [RemovalOutcome], items: [BinItem]) {
        removing = false
        showConfirm = false
        acceptPermanent = false
        self.outcomes = outcomes
        showResults = true
        let succeeded = outcomes.filter(\.ok)
        let payloads = Set(succeeded.map(\.payload))
        if var scan {
            scan.tree = TreeEdit.removing(paths: payloads, from: scan.tree)
            scan.candidates.removeAll { payloads.contains($0.path) }
            self.scan = scan
        }
        bin.removeAll { payloads.contains($0.payload) }
        let bytes = items.filter { payloads.contains($0.payload) }.reduce(Int64(0)) { $0 + $1.bytes }
        if bytes > 0 {
            banner = "Freed \(ByteFormat.string(bytes)). Files that went to the Trash can be put back."
            try? ScanStore.appendLog(CleanupLogEntry(date: Date(), bytes: bytes, titles: succeeded.map(\.title)))
        } else if succeeded.isEmpty {
            banner = "Nothing was removed."
        }
    }

    private func applyHotkey() {
        if settings.hotkeyEnabled {
            hotkeys.register(keyCode: settings.hotkeyCode, modifiers: settings.hotkeyModifiers)
        } else {
            hotkeys.unregister()
        }
    }

    private func refreshAlertAuthorization() {
        Task {
            let status = await notifier.status()
            alertsAllowed = status == .authorized
        }
    }

    private func observeWindows() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let window = note.object as? NSWindow, window.title == "Headroom" else { return }
            DispatchQueue.main.async {
                let stillOpen = NSApp.windows.contains { $0.title == "Headroom" && $0.isVisible && $0 != window }
                if !stillOpen {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
}
