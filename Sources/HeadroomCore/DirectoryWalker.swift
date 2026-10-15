import Foundation

public enum DirectoryWalker {
    private static let collapsedNames: Set<String> = [
        "node_modules", ".git", "DerivedData", ".build", ".next", ".turbo", "Pods", "__pycache__"
    ]
    private static let skipNames: Set<String> = [
        ".Trash", ".Trashes", ".DocumentRevisions-V100", ".TemporaryItems",
        ".fseventsd", ".Spotlight-V100", ".MobileBackups"
    ]

    public static func scan(
        root: URL,
        home: String,
        onProgress: @escaping (WalkProgress) -> Void
    ) throws -> ScanResult {
        let root = root.standardizedFileURL
        let state = WalkState(home: SecurityGate.standardized(home), volume: volumeID(root), onProgress: onProgress)
        let node = try walk(root, depth: 0, state: state) ?? FileNode(
            name: root.lastPathComponent,
            path: root.path,
            allocatedBytes: 0,
            isDirectory: true,
            partial: true
        )
        let candidates = state.candidates.sorted { $0.bytes > $1.bytes }
        return ScanResult(
            root: root.path,
            scannedAt: Date(),
            tree: node,
            candidates: candidates,
            partial: node.partial || state.partial
        )
    }

    private static func walk(_ url: URL, depth: Int, state: WalkState) throws -> FileNode? {
        try Task.checkCancellation()
        state.bump(url.path)
        let name = url.lastPathComponent
        if skipNames.contains(name) { return nil }
        if depth > 0, let volume = state.volume, let here = volumeID(url), here != volume {
            return nil
        }
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isUbiquitousItemKey])
        if values?.isSymbolicLink == true {
            return FileNode(name: name, path: url.path, allocatedBytes: 0, isDirectory: false)
        }
        let isDirectory = values?.isDirectory ?? true
        if !isDirectory {
            let size = allocated(url)
            return FileNode(name: name, path: url.path, allocatedBytes: size, isDirectory: false)
        }

        let rule = Classifier.rule(for: url.path, home: state.home)
        let containsGit = hasGitChild(url)
        if rule != nil || collapsedNames.contains(name) || depth >= 8 {
            let summed = sumTree(url)
            if let rule {
                consider(rule, path: url.path, bytes: summed.bytes, containsGit: containsGit, state: state)
            }
            return FileNode(
                name: name,
                path: url.path,
                allocatedBytes: summed.bytes,
                isDirectory: true,
                partial: summed.partial,
                containsGit: containsGit
            )
        }

        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .fileAllocatedSizeKey, .isUbiquitousItemKey],
                options: []
            )
        } catch {
            state.partial = true
            return FileNode(name: name, path: url.path, allocatedBytes: 0, isDirectory: true, partial: true, containsGit: containsGit)
        }

        var nodes: [FileNode] = []
        var partial = false
        for child in children {
            if let node = try walk(child, depth: depth + 1, state: state) {
                if node.partial { partial = true }
                nodes.append(node)
            }
        }
        nodes.sort { $0.allocatedBytes > $1.allocatedBytes }
        let kept = Array(nodes.prefix(24))
        let rest = nodes.dropFirst(24)
        var displayed = kept
        let otherBytes = rest.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        if otherBytes > 0 {
            displayed.append(FileNode(
                name: "Other",
                path: url.path + "::other",
                allocatedBytes: otherBytes,
                isDirectory: true
            ))
        }
        let total = displayed.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        return FileNode(
            name: name,
            path: url.path,
            allocatedBytes: total,
            isDirectory: true,
            children: displayed,
            partial: partial,
            containsGit: containsGit
        )
    }

    private static func consider(_ rule: CleanupRule, path: String, bytes: Int64, containsGit: Bool, state: WalkState) {
        guard bytes > 0 else { return }
        let name = (path as NSString).lastPathComponent
        if containsGit && !SecurityGate.regenerableNames.contains(name) { return }
        guard SecurityGate.denyReason(path) == nil else { return }
        state.candidates.append(CleanupCandidate(
            path: path,
            bytes: bytes,
            title: rule.title,
            detail: rule.detail,
            tier: rule.tier,
            category: rule.category,
            ruleID: rule.id
        ))
    }

    private static func hasGitChild(_ url: URL) -> Bool {
        let git = url.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: git.path, isDirectory: &isDir)
    }

    private static func sumTree(_ url: URL) -> (bytes: Int64, partial: Bool) {
        var total: Int64 = 0
        var partial = false
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileAllocatedSizeKey, .isSymbolicLinkKey, .isRegularFileKey],
            options: [],
            errorHandler: { _, _ in
                partial = true
                return true
            }
        ) else {
            return (0, true)
        }
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.isSymbolicLinkKey, .fileAllocatedSizeKey, .isRegularFileKey])
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            // Allocated size only. Reading bytes would pull down iCloud placeholders.
            if values?.isRegularFile == true {
                total += Int64(values?.fileAllocatedSize ?? 0)
            }
        }
        return (total, partial)
    }

    private static func allocated(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileAllocatedSizeKey, .isUbiquitousItemKey])
        return Int64(values?.fileAllocatedSize ?? 0)
    }

    private static func volumeID(_ url: URL) -> String? {
        try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    }
}

private final class WalkState {
    let home: String
    let volume: String?
    let onProgress: (WalkProgress) -> Void
    var candidates: [CleanupCandidate] = []
    var partial = false
    private var visited = 0
    private var lastCallback = Date.distantPast

    init(home: String, volume: String?, onProgress: @escaping (WalkProgress) -> Void) {
        self.home = home
        self.volume = volume
        self.onProgress = onProgress
    }

    func bump(_ path: String) {
        visited += 1
        let now = Date()
        if now.timeIntervalSince(lastCallback) > 0.2 {
            lastCallback = now
            onProgress(WalkProgress(currentPath: path, visitedDirectories: visited))
        }
    }
}
