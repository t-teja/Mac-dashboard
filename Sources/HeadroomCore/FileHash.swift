import CryptoKit
import Foundation

public enum FileHash {
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Prefix(of url: URL, count: Int) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let chunk = try handle.read(upToCount: count) ?? Data()
        var hasher = SHA256()
        hasher.update(data: chunk)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
