import Foundation

public enum ByteFormat {
    /// Decimal units, the same scale Finder uses for disk sizes.
    public static func string(_ bytes: Int64) -> String {
        let sign = bytes < 0 ? "−" : ""
        var value = Double(abs(bytes))
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        if index == 0 {
            return "\(sign)\(Int(value)) \(units[index])"
        }
        if value >= 10 {
            return String(format: "%@%.0f %@", sign, value, units[index])
        }
        return String(format: "%@%.1f %@", sign, value, units[index])
    }

    public static func signedDelta(_ bytes: Int64) -> String {
        if bytes > 0 { return "+" + string(bytes) }
        return string(bytes)
    }

    public static func rate(_ bytesPerSecond: Double) -> String {
        string(Int64(max(0, bytesPerSecond))) + "/s"
    }
}

public enum TimeFormat {
    public static func uptime(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
