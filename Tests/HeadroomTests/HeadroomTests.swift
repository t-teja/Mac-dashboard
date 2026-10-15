import Foundation
import Testing
@testable import HeadroomCore

@Test func byteFormatUsesDecimalUnits() {
    #expect(ByteFormat.string(0) == "0 B")
    #expect(ByteFormat.string(999) == "999 B")
    #expect(ByteFormat.string(1_500) == "1.5 KB")
    #expect(ByteFormat.string(12_000_000_000) == "12 GB")
    #expect(ByteFormat.signedDelta(-2_000_000_000) == "−2.0 GB")
    #expect(ByteFormat.signedDelta(3_000_000_000) == "+3.0 GB")
}

@Test func gateRejectsPersonalAndSystemPaths() {
    let home = "/Users/ada"
    #expect(SecurityGate.denyReason("/Users/ada") != nil)
    #expect(SecurityGate.denyReason("/Users/ada/Documents/notes.txt") != nil)
    #expect(SecurityGate.denyReason("/Users/ada/Desktop/shot.png") != nil)
    #expect(SecurityGate.denyReason("/Users/ada/Library/Mail/box") != nil)
    #expect(SecurityGate.denyReason("/Users/ada/Library/Containers/com.example.app") != nil)
    #expect(SecurityGate.denyReason("/Users/ada/Library/Keychains/login.keychain-db") != nil)
    #expect(SecurityGate.denyReason("/System/Library/Kernels/kernel") != nil)
    #expect(SecurityGate.denyReason("/Applications/Safari.app") != nil)
    #expect(SecurityGate.denyReason("/Users/ada/project/.git/config") != nil)
    #expect(SecurityGate.denyReason("/Users/ada/.npm/\"quoted\"") != nil)
    #expect(SecurityGate.denyReason("/Users/ada/.npm") == nil)
    #expect(SecurityGate.denyReason("/Users/ada/Library/Developer/Xcode/DerivedData/App-abc") == nil)
    #expect(SecurityGate.denyReason("/Volumes/Extra/code/node_modules") == nil)
    #expect(Classifier.rule(for: "/Users/ada/Documents/tax.pdf", home: home) == nil)
    #expect(Classifier.rule(for: "/Users/ada/.npm", home: home)?.id == "npm.cache")
    #expect(Classifier.rule(for: "/Users/ada/Library/Developer/Xcode/DerivedData", home: home)?.tier == .safe)
    #expect(Classifier.rule(for: "/Volumes/Extra/app/node_modules", home: home)?.id == "node.modules")
    #expect(
        Classifier.rule(
            for: "/Users/ada/Library/Android/sdk/system-images/android-34/google_apis/arm64-v8a",
            home: home
        )?.id == "android.images"
    )
}

@Test func icicleSplitsSpaceWithoutOverlap() {
    let childA = FileNode(name: "A", path: "/A", allocatedBytes: 50, isDirectory: true)
    let childB = FileNode(name: "B", path: "/B", allocatedBytes: 50, isDirectory: true)
    let root = FileNode(name: "root", path: "/", allocatedBytes: 100, isDirectory: true, children: [childA, childB])
    let rects = StrataLayout.icicle(node: root, width: 203, rowHeight: 20, rows: 2, gap: 3)
    let row = rects.filter { $0.depth == 1 }
    #expect(row.count == 2)
    #expect(abs(row[0].width - 100) < 0.001)
    #expect(abs(row[1].width - 100) < 0.001)
    #expect(row[1].x >= row[0].x + row[0].width)
}

@Test func treeRemovalSubtractsFromAncestors() {
    let leaf = FileNode(name: "cache", path: "/Users/ada/.npm", allocatedBytes: 10, isDirectory: true)
    let keep = FileNode(name: "src", path: "/Users/ada/src", allocatedBytes: 5, isDirectory: true)
    let root = FileNode(name: "ada", path: "/Users/ada", allocatedBytes: 15, isDirectory: true, children: [leaf, keep])
    let edited = TreeEdit.removing(paths: ["/Users/ada/.npm"], from: root)
    #expect(edited.allocatedBytes == 5)
    #expect(edited.children.map(\.path) == ["/Users/ada/src"])
}

@Test func alertsRespectSustainAndCooldown() {
    let volume = VolumeInfo(
        name: "Macintosh HD",
        path: "/",
        totalBytes: 500_000_000_000,
        freeBytes: 5_000_000_000,
        availableBytes: 8_000_000_000,
        isInternal: true
    )
    let snapshot = SystemSnapshot(
        capturedAt: Date(),
        cpu: CPUSample(usage: 0.95, user: 0.9, system: 0.05, idle: 0.05, cores: []),
        memory: MemorySample(
            totalBytes: 16,
            appBytes: 8,
            wiredBytes: 2,
            compressedBytes: 1,
            cachedBytes: 1,
            freeBytes: 4,
            pressure: .warning
        ),
        diskIO: DiskIOSample(),
        network: NetworkSample(),
        thermal: .nominal,
        battery: nil,
        processes: [],
        volumes: [volume],
        uptime: 10
    )
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let first = AlertEngine.evaluate(
        snapshot: snapshot,
        settings: .standard,
        state: AlertState(),
        newlyReviewableBytes: 0,
        now: now
    )
    #expect(first.active.contains { $0.kind == .disk })
    #expect(first.active.contains { $0.kind == .memory })
    #expect(!first.active.contains { $0.kind == .cpu })
    let later = AlertEngine.evaluate(
        snapshot: snapshot,
        settings: .standard,
        state: first.state,
        newlyReviewableBytes: 0,
        now: now.addingTimeInterval(121)
    )
    #expect(later.active.contains { $0.kind == .cpu })
    #expect(later.notify.contains { $0.kind == .cpu })
    let cooled = AlertEngine.evaluate(
        snapshot: snapshot,
        settings: .standard,
        state: later.state,
        newlyReviewableBytes: 0,
        now: now.addingTimeInterval(130)
    )
    #expect(!cooled.notify.contains { $0.kind == .cpu })
}

@Test func postcardIsMondayOnly() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    // 2024-01-08 00:00:00 UTC is a Monday. 1_704_700_800 is 08:00 that day.
    let monday = Date(timeIntervalSince1970: 1_704_672_000)
    #expect(calendar.component(.weekday, from: monday) == 2)
    #expect(PostcardMaker.shouldSend(now: monday.addingTimeInterval(10 * 3600), lastSent: nil, enabled: true, calendar: calendar))
    #expect(!PostcardMaker.shouldSend(now: monday.addingTimeInterval(8 * 3600), lastSent: nil, enabled: true, calendar: calendar))
    #expect(!PostcardMaker.shouldSend(now: monday.addingTimeInterval(10 * 3600), lastSent: monday, enabled: true, calendar: calendar))
    let tuesday = monday.addingTimeInterval(86_400)
    #expect(!PostcardMaker.shouldSend(now: tuesday.addingTimeInterval(10 * 3600), lastSent: nil, enabled: true, calendar: calendar))
}

@Test func duplicateExtrasAlwaysLeaveOne() {
    let older = DuplicateFile(path: "/tmp/a", bytes: 10, modified: Date(timeIntervalSince1970: 10))
    let newer = DuplicateFile(path: "/tmp/b", bytes: 10, modified: Date(timeIntervalSince1970: 20))
    let group = DuplicateGroup(hash: String(repeating: "a", count: 64), files: [newer, older])
    let extras = DuplicateGrouper.extras(in: group, keeping: "/tmp/b")
    #expect(extras.map { $0.path } == ["/tmp/a"])
    #expect(DuplicateGrouper.extras(in: DuplicateGroup(hash: group.hash, files: [newer]), keeping: "/tmp/b").isEmpty)
    let grouped = DuplicateGrouper.group([
        (older, group.hash),
        (newer, group.hash),
        (older, group.hash)
    ])
    #expect(grouped.count == 1)
    #expect(grouped[0].files.count == 2)
}

@Test func scriptHasNoRmAndRejectsADocument() {
    let home = "/Users/ada"
    let cache = BinItem(
        id: "1", title: "npm", subtitle: "", bytes: 10, method: .trash, kind: .cache,
        payload: "/Users/ada/.npm", expectedHash: nil, bundleID: nil
    )
    let document = BinItem(
        id: "2", title: "tax", subtitle: "", bytes: 10, method: .trash, kind: .cache,
        payload: "/Users/ada/Documents/tax.pdf", expectedHash: nil, bundleID: nil
    )
    let badDocker = BinItem(
        id: "3", title: "image", subtitle: "", bytes: 10, method: .dockerImage, kind: .osImage,
        payload: "not-an-id", expectedHash: nil, bundleID: nil
    )
    let script = CleanupPlan.script([cache, document, badDocker], home: home)
    #expect(script.range(of: #"\brm\b"#, options: .regularExpression) == nil)
    #expect(script.contains("trash_path"))
    #expect(script.contains("/Users/ada/.npm"))
    #expect(!script.contains("trash_path '/Users/ada/Documents/tax.pdf'"))
    #expect(!script.contains("docker image rm"))
    let vetted = CleanupPlan.vet([cache, document, badDocker], home: home)
    #expect(vetted.allowed.map(\.id) == ["1"])
    #expect(vetted.rejected.count == 2)
}

@Test func processDenialList() {
    #expect(ProcessControl.denial(name: "Finder", pid: 40, uid: 501, myPid: 99, myUid: 501) != nil)
    #expect(ProcessControl.denial(name: "Chrome", pid: 99, uid: 501, myPid: 99, myUid: 501) != nil)
    #expect(ProcessControl.denial(name: "Chrome", pid: 40, uid: 0, myPid: 99, myUid: 501) != nil)
    #expect(ProcessControl.denial(name: "Chrome", pid: 40, uid: 501, myPid: 99, myUid: 501) == nil)
}

@Test func scanDiff() {
    let previous = FileNode(name: "home", path: "/Users/ada", allocatedBytes: 100, isDirectory: true, children: [
        FileNode(name: "Library", path: "/Users/ada/Library", allocatedBytes: 80, isDirectory: true)
    ])
    let current = FileNode(name: "home", path: "/Users/ada", allocatedBytes: 150, isDirectory: true, children: [
        FileNode(name: "Library", path: "/Users/ada/Library", allocatedBytes: 140, isDirectory: true)
    ])
    let deltas = ScanDiff.topLevelDeltas(previous: previous, current: current, minimumBytes: 1)
    #expect(deltas.first?.bytes == 60)
}

@Test func hashOfATemporaryFile() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("headroom-hash-\(UUID().uuidString).txt")
    try Data("headroom".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let digest = try FileHash.sha256(of: url)
    #expect(digest.count == 64)
    let again = try FileHash.sha256(of: url)
    #expect(digest == again)
}

@Test func displayPathHidesTheAccountName() {
    let home = "/Users/ada"
    let shown = SecurityGate.displayPath("/Users/ada/Library/Caches/npm", home: home)
    #expect(shown == "~/Library/Caches/npm")
    #expect(!shown.contains("ada"))
    #expect(SecurityGate.displayPath(home, home: home) == "~")
    #expect(SecurityGate.displayPath("/Applications/Safari.app", home: home) == "/Applications/Safari.app")
}

@Test func installerGate() {
    let home = "/Users/ada"
    #expect(SecurityGate.osImageTrashReason("/Applications/Install macOS Sequoia.app", home: home) == nil)
    #expect(SecurityGate.osImageTrashReason("/Users/ada/Downloads/Restore.ipsw", home: home) == nil)
    #expect(SecurityGate.osImageTrashReason("/Applications/Safari.app", home: home) != nil)
    #expect(SecurityGate.osImageTrashReason("/Users/ada/Library/Android/sdk/system-images", home: home) != nil)
    #expect(SecurityGate.osImageTrashReason(
        "/Users/ada/Library/Android/sdk/system-images/android-34/google_apis/arm64-v8a",
        home: home
    ) == nil)
}
