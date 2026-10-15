import Foundation

public enum ScanStore {
    public static func directory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Mac Space Saver", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    public static func save(_ result: ScanResult) throws {
        let folder = try directory()
        let latest = folder.appendingPathComponent(fileName(result.root, suffix: "latest"))
        let previous = folder.appendingPathComponent(fileName(result.root, suffix: "previous"))
        if FileManager.default.fileExists(atPath: latest.path) {
            if FileManager.default.fileExists(atPath: previous.path) {
                try FileManager.default.removeItem(at: previous)
            }
            try FileManager.default.moveItem(at: latest, to: previous)
        }
        let data = try encoder.encode(result)
        try data.write(to: latest, options: .atomic)
    }

    public static func loadLatest(root: String) -> ScanResult? {
        load(root: root, suffix: "latest")
    }

    public static func loadPrevious(root: String) -> ScanResult? {
        load(root: root, suffix: "previous")
    }

    public static func appendLog(_ entry: CleanupLogEntry) throws {
        var entries = loadLog()
        entries.append(entry)
        let folder = try directory()
        let data = try encoder.encode(entries)
        try data.write(to: folder.appendingPathComponent("cleanup-log.json"), options: .atomic)
    }

    public static func loadLog() -> [CleanupLogEntry] {
        guard let folder = try? directory() else { return [] }
        let url = folder.appendingPathComponent("cleanup-log.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([CleanupLogEntry].self, from: data)) ?? []
    }

    public static func freed(since: Date) -> Int64 {
        loadLog().filter { $0.date >= since }.reduce(0) { $0 + $1.bytes }
    }

    private static func load(root: String, suffix: String) -> ScanResult? {
        guard let folder = try? directory() else { return nil }
        let url = folder.appendingPathComponent(fileName(root, suffix: suffix))
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ScanResult.self, from: data)
    }

    private static func fileName(_ root: String, suffix: String) -> String {
        let digest = root.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        return "scan-\(String(digest, radix: 16))-\(suffix).json"
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
