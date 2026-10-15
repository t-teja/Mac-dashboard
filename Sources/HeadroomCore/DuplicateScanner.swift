import Foundation

public struct DuplicateProgress: Sendable, Equatable {
    public var label: String
    public init(label: String) { self.label = label }
}

public enum DuplicateScanner {
    /// Groups regular files by size, then by a short hash, then by a full hash.
    /// iCloud placeholders are skipped so the scan does not download them.
    public static func find(
        roots: [URL],
        minimumBytes: Int64,
        onProgress: @escaping (DuplicateProgress) -> Void
    ) throws -> [DuplicateGroup] {
        onProgress(DuplicateProgress(label: "Listing files"))
        var files: [DuplicateFile] = []
        for root in roots {
            try collect(root, minimumBytes: minimumBytes, into: &files)
            try Task.checkCancellation()
        }
        onProgress(DuplicateProgress(label: "Listed \(files.count) files"))
        let bySize = Dictionary(grouping: files, by: \.bytes).filter { $0.value.count > 1 && $0.key >= minimumBytes }
        var candidates: [DuplicateFile] = bySize.values.flatMap { $0 }
        if candidates.count > 20_000 {
            candidates = Array(candidates.prefix(20_000))
            onProgress(DuplicateProgress(label: "Hashing the first 20,000 size matches"))
        } else {
            onProgress(DuplicateProgress(label: "Hashing \(candidates.count) size matches"))
        }

        var partial: [(DuplicateFile, String)] = []
        for file in candidates {
            try Task.checkCancellation()
            let url = URL(fileURLWithPath: file.path)
            if let digest = try? FileHash.sha256Prefix(of: url, count: 64 * 1024) {
                partial.append((file, digest))
            }
        }
        let partialGroups = Dictionary(grouping: partial, by: { $0.1 }).filter { $0.value.count > 1 }
        var full: [(DuplicateFile, String)] = []
        let pending = partialGroups.values.flatMap { $0.map(\.0) }
        onProgress(DuplicateProgress(label: "Confirming \(pending.count) files"))
        for file in pending {
            try Task.checkCancellation()
            let url = URL(fileURLWithPath: file.path)
            if let digest = try? FileHash.sha256(of: url) {
                full.append((file, digest))
            }
        }
        return DuplicateGrouper.group(full)
    }

    private static func collect(_ root: URL, minimumBytes: Int64, into files: inout [DuplicateFile]) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileAllocatedSizeKey,
                .contentModificationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
            ],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return }
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isSymbolicLinkKey, .fileAllocatedSizeKey,
            .contentModificationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
        ]
        for case let item as URL in enumerator {
            try Task.checkCancellation()
            let values = try? item.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values?.isUbiquitousItem == true, values?.ubiquitousItemDownloadingStatus != .current {
                continue
            }
            guard values?.isRegularFile == true else { continue }
            let bytes = Int64(values?.fileAllocatedSize ?? 0)
            guard bytes >= minimumBytes else { continue }
            if SecurityGate.duplicateFileReason(item.path) != nil { continue }
            files.append(DuplicateFile(
                path: item.path,
                bytes: bytes,
                modified: values?.contentModificationDate ?? .distantPast
            ))
        }
    }
}
