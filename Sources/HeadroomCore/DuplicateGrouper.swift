import Foundation

public enum DuplicateGrouper {
    public static func group(_ files: [(DuplicateFile, String)]) -> [DuplicateGroup] {
        var buckets: [String: [DuplicateFile]] = [:]
        for (file, hash) in files where hash.count >= 64 {
            buckets[hash, default: []].append(file)
        }
        return buckets.compactMap { hash, files in
            let unique = Dictionary(grouping: files, by: \.path).compactMap { $0.value.first }
            guard unique.count > 1 else { return nil }
            let sorted = unique.sorted { $0.modified > $1.modified }
            return DuplicateGroup(hash: hash, files: sorted)
        }
        .sorted { $0.wastedBytes > $1.wastedBytes }
    }

    public static func keeper(in group: DuplicateGroup, policy: KeepPolicy) -> DuplicateFile? {
        switch policy {
        case .newest:
            return group.files.max { $0.modified < $1.modified }
        case .oldest:
            return group.files.min { $0.modified < $1.modified }
        }
    }

    /// Every file except the one being kept. Never returns the whole group.
    public static func extras(in group: DuplicateGroup, keeping path: String) -> [DuplicateFile] {
        let keep = group.files.first { $0.path == path } ?? keeper(in: group, policy: .newest)
        guard let keep, group.files.count > 1 else { return [] }
        return group.files.filter { $0.path != keep.path }
    }
}
