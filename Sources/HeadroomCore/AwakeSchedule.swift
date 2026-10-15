import Foundation

public enum AwakeChoice: String, Codable, CaseIterable, Sendable {
    case untilOff
    case minutes30
    case hour1
    case hours2
    case untilMorning

    public var title: String {
        switch self {
        case .untilOff: return "Until I turn it off"
        case .minutes30: return "30 minutes"
        case .hour1: return "1 hour"
        case .hours2: return "2 hours"
        case .untilMorning: return "Until morning"
        }
    }
}

public enum AwakeSchedule {
    public static let morningHour = 7

    /// `nil` means the Mac stays awake until the switch is turned off.
    public static func deadline(from start: Date, choice: AwakeChoice, calendar: Calendar = .current) -> Date? {
        switch choice {
        case .untilOff:
            return nil
        case .minutes30:
            return start.addingTimeInterval(30 * 60)
        case .hour1:
            return start.addingTimeInterval(60 * 60)
        case .hours2:
            return start.addingTimeInterval(2 * 60 * 60)
        case .untilMorning:
            var parts = calendar.dateComponents([.year, .month, .day], from: start)
            parts.hour = morningHour
            parts.minute = 0
            parts.second = 0
            let morning = calendar.date(from: parts) ?? start
            if morning > start { return morning }
            return calendar.date(byAdding: .day, value: 1, to: morning)
        }
    }

    public static func isExpired(now: Date, until: Date?) -> Bool {
        guard let until else { return false }
        return now >= until
    }

    public static func status(until: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let until else { return "Awake until you turn it off." }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(until, inSameDayAs: now) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "Awake until \(formatter.string(from: until))."
        }
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Awake until \(formatter.string(from: until))."
    }
}
