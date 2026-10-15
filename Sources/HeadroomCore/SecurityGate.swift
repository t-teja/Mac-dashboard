import Foundation

/// The last word on what Mac Space Saver is willing to remove.
/// A matching cleanup rule is not enough. This gate has to agree, again, at the moment of removal.
public enum SecurityGate {
    public static let regenerableNames: Set<String> = [
        "node_modules", ".next", ".turbo", "DerivedData", ".build"
    ]

    public static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    public static func denyReason(_ raw: String) -> String? {
        if raw.unicodeScalars.contains(where: { character in
            character == "\0" || character == "\"" || character == "'" || character == "\\"
                || character == "\n" || character == "\r" || character == "$" || character == "`"
        }) {
            return "That path contains characters Mac Space Saver will not remove."
        }
        let path = standardized(raw)
        if !path.hasPrefix("/") { return "Path must be absolute." }
        let parts = path.split(separator: "/").map(String.init)
        if parts.contains(where: { $0 == "." || $0 == ".." }) {
            return "Path is not valid."
        }
        if parts.count < 3 { return "That path is too broad to remove." }
        if parts.contains(".git") { return "Git internals stay put." }

        let blockedRoots = ["/System", "/usr", "/bin", "/sbin", "/dev", "/private", "/Library", "/opt", "/cores", "/Applications"]
        for root in blockedRoots where path == root || path.hasPrefix(root + "/") {
            return "System locations stay put."
        }
        if path == "/Volumes" || path == "/Users" { return "That path is too broad to remove." }
        if parts.count == 2, parts[0] == "Users" { return "A home folder is too broad to remove." }
        if parts.count == 2, parts[0] == "Volumes" { return "A whole volume is too broad to remove." }
        if let reason = deniedUserArea(parts) { return reason }
        return nil
    }

    /// Duplicate files may live in Documents or Pictures. Directories, mail, and secrets still cannot.
    public static func duplicateFileReason(_ raw: String) -> String? {
        let path = standardized(raw)
        if let reason = blockedCharacters(raw) { return reason }
        let parts = path.split(separator: "/").map(String.init)
        if !path.hasPrefix("/") || parts.count < 4 { return "That file is too broad to remove." }
        if parts.contains(".git") { return "Git internals stay put." }
        let blockedRoots = ["/System", "/usr", "/bin", "/sbin", "/dev", "/private", "/Library", "/opt", "/cores"]
        for root in blockedRoots where path == root || path.hasPrefix(root + "/") {
            return "System locations stay put."
        }
        if parts.count >= 4, parts[0] == "Users" {
            let library = parts[2]
            if library == "Library", parts.count >= 4 {
                let area = parts[3]
                let secret: Set<String> = [
                    "Mail", "Messages", "Keychains", "IdentityServices", "Cookies",
                    "Accounts", "HomeKit", "Biome", "Group Containers", "Containers",
                    "CloudStorage", "Mobile Documents"
                ]
                if secret.contains(area) { return "That library folder stays put." }
            }
        }
        return nil
    }

    public static func appBundleReason(_ raw: String, bundleID: String, home: String) -> String? {
        let bundleID = bundleID.trimmingCharacters(in: .whitespaces)
        if bundleID.isEmpty || bundleID.hasPrefix("com.apple.") {
            return "Apple system apps stay installed."
        }
        guard isSafeBundleID(bundleID) else { return "That bundle id is not one Mac Space Saver will remove." }
        let path = standardized(raw)
        if !path.hasSuffix(".app") { return "That is not an app." }
        if path.contains(".app/") { return "That app is inside another app." }
        let homes = [
            "/Applications/",
            standardized(home) + "/Applications/"
        ]
        guard homes.contains(where: { path.hasPrefix($0) }) else {
            return "Apps are only removed from the Applications folders."
        }
        let remainder = homes.compactMap { prefix -> String? in
            path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
        }.first ?? ""
        if remainder.contains("/") { return "That app is nested. Remove the outer app instead." }
        return nil
    }

    public static func leftoverReason(_ raw: String, bundleID: String, home: String) -> String? {
        guard isSafeBundleID(bundleID), !bundleID.hasPrefix("com.apple.") else {
            return "That bundle id is not one Mac Space Saver will remove."
        }
        let path = standardized(raw)
        let home = standardized(home)
        let allowed = leftoverPaths(bundleID: bundleID, home: home)
        guard allowed.contains(path) else { return "That leftover is outside the known list." }
        return nil
    }

    public static func leftoverPaths(bundleID: String, home: String) -> [String] {
        let home = standardized(home)
        let relative = [
            "Library/Preferences/\(bundleID).plist",
            "Library/Caches/\(bundleID)",
            "Library/Logs/\(bundleID)",
            "Library/Application Support/\(bundleID)",
            "Library/Containers/\(bundleID)",
            "Library/Saved Application State/\(bundleID).savedState",
            "Library/WebKit/\(bundleID)",
            "Library/HTTPStorages/\(bundleID)"
        ]
        return relative.map { home + "/" + $0 }
    }

    public static func osImageTrashReason(_ raw: String, home: String) -> String? {
        let path = standardized(raw)
        let home = standardized(home)
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        if path.contains("/Library/Android/sdk/system-images/") {
            if let reason = denyReason(path) { return reason }
            let marker = "/Library/Android/sdk/system-images/"
            guard let range = path.range(of: marker) else { return "That is not an Android system image." }
            let rest = path[range.upperBound...]
            let pieces = rest.split(separator: "/")
            if pieces.count < 3 { return "Choose a single system image, not the whole folder." }
            return nil
        }
        if ext == "ipsw" {
            let allowedParents = [
                home + "/Downloads",
                home + "/Desktop",
                home + "/Applications"
            ]
            let parent = (path as NSString).deletingLastPathComponent
            guard allowedParents.contains(parent) else {
                return "Installer files are only taken from Downloads, Desktop, or Applications."
            }
            return nil
        }
        if ext == "app", name.hasPrefix("Install macOS") {
            let allowedParents = [
                "/Applications",
                home + "/Downloads",
                home + "/Desktop",
                home + "/Applications"
            ]
            let parent = (path as NSString).deletingLastPathComponent
            guard allowedParents.contains(parent) else {
                return "macOS installers are only taken from Applications, Downloads, or the Desktop."
            }
            return nil
        }
        return "That is not an OS image Mac Space Saver knows how to remove."
    }

    public static func validRuntimeIdentifier(_ raw: String) -> Bool {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...180).contains(id.count) else { return false }
        return id.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "." || character == "_"
        }
    }

    public static func validDockerID(_ raw: String) -> Bool {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (12...64).contains(id.count) else { return false }
        return id.allSatisfy { ($0 >= "0" && $0 <= "9") || ($0 >= "a" && $0 <= "f") || ($0 >= "A" && $0 <= "F") }
    }

    public static func isSafeBundleID(_ raw: String) -> Bool {
        guard (3...220).contains(raw.count) else { return false }
        return raw.allSatisfy { character in
            character.isLetter || character.isNumber || character == "." || character == "-"
        }
    }

    public static func relativeToHome(_ path: String, home: String) -> String? {
        let path = standardized(path)
        let home = standardized(home)
        if path == home { return "" }
        let prefix = home + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }

    /// A path safe to show. The account name in `/Users/…` is replaced with `~`.
    public static func displayPath(_ path: String, home: String) -> String {
        guard let relative = relativeToHome(path, home: home) else { return path }
        return relative.isEmpty ? "~" : "~/" + relative
    }

    private static func blockedCharacters(_ raw: String) -> String? {
        if raw.unicodeScalars.contains(where: { character in
            character == "\0" || character == "\"" || character == "'" || character == "\\"
                || character == "\n" || character == "\r" || character == "$" || character == "`"
        }) {
            return "That path contains characters Mac Space Saver will not remove."
        }
        return nil
    }

    private static func deniedUserArea(_ parts: [String]) -> String? {
        guard parts.count >= 3, parts[0] == "Users" else { return nil }
        let rest = Array(parts.dropFirst(2))
        if rest.isEmpty { return "A home folder is too broad to remove." }
        let top = rest[0]
        let personal: Set<String> = ["Documents", "Desktop", "Pictures", "Movies", "Music", "Public"]
        if personal.contains(top) { return "Personal folders are never cleaned up from here." }
        if top == "Library" {
            if rest.count == 1 { return "The Library folder is too broad to remove." }
            let second = rest[1]
            let always: Set<String> = [
                "Mail", "Messages", "Photos", "Mobile Documents", "CloudStorage",
                "Keychains", "IdentityServices", "Cookies", "Accounts", "HomeKit",
                "Biome", "IntelligencePlatform", "Group Containers", "Containers",
                "PersonalizationPortrait", "StatusKit"
            ]
            if always.contains(second) { return "That library folder stays put." }
            if rest.count == 2 {
                let tooBroad: Set<String> = ["Caches", "Application Support", "Developer", "Preferences", "Logs"]
                // Logs is a review candidate as a whole folder, so it is allowed.
                if second == "Logs" { return nil }
                if tooBroad.contains(second) { return "That library folder is too broad to remove." }
            }
        }
        return nil
    }
}
