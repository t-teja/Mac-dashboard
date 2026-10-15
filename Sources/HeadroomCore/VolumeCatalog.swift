import Foundation

public enum VolumeCatalog {
    public static func current() -> [VolumeInfo] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey,
            .volumeIsBrowsableKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: []) ?? []
        var volumes: [VolumeInfo] = []
        var seen = Set<String>()
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.volumeIsLocal == false { continue }
            if values.volumeIsBrowsable != true { continue }
            let total = Int64(values.volumeTotalCapacity ?? 0)
            guard total > 0 else { continue }
            let path = url.path
            if seen.contains(path) { continue }
            seen.insert(path)
            let free = Int64(values.volumeAvailableCapacity ?? 0)
            let available = Int64(values.volumeAvailableCapacityForImportantUsage ?? free)
            volumes.append(VolumeInfo(
                name: values.volumeName ?? path,
                path: path,
                totalBytes: total,
                freeBytes: free,
                availableBytes: max(free, available),
                isInternal: values.volumeIsInternal ?? false
            ))
        }
        return volumes.sorted { lhs, rhs in
            if lhs.isInternal != rhs.isInternal { return lhs.isInternal }
            return lhs.totalBytes > rhs.totalBytes
        }
    }
}
