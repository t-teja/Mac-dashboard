import Foundation

public struct VettedBin: Sendable {
    public var allowed: [BinItem]
    public var rejected: [(BinItem, String)]

    public init(allowed: [BinItem], rejected: [(BinItem, String)]) {
        self.allowed = allowed
        self.rejected = rejected
    }
}

public enum CleanupPlan {
    public static func vet(_ items: [BinItem], home: String) -> VettedBin {
        var allowed: [BinItem] = []
        var rejected: [(BinItem, String)] = []
        var seen = Set<String>()
        for item in items {
            let key = item.kind.rawValue + "|" + item.method.rawValue + "|" + item.payload
            if seen.contains(key) { continue }
            seen.insert(key)
            if let reason = reason(for: item, home: home) {
                rejected.append((item, reason))
            } else {
                allowed.append(item)
            }
        }
        return VettedBin(allowed: allowed, rejected: rejected)
    }

    public static func overlapNotes(_ items: [BinItem]) -> [String] {
        let paths = items.filter { $0.method == .trash }.map { SecurityGate.standardized($0.payload) }
        var notes: [String] = []
        for path in paths {
            for other in paths where other != path && (path.hasPrefix(other + "/") || other.hasPrefix(path + "/")) && path.count > other.count {
                let inner = (path as NSString).lastPathComponent
                let outer = (other as NSString).lastPathComponent
                notes.append("\(inner) is already inside \(outer).")
            }
        }
        return notes
    }

    /// A script the user can read. It moves files to the Trash. It does not call rm.
    public static func script(_ items: [BinItem], home: String) -> String {
        let vetted = vet(items, home: home)
        var lines: [String] = []
        lines.append("#!/bin/zsh")
        lines.append("# Headroom cleanup plan")
        lines.append("# Files go to the Trash. Simulator runtimes and Docker images do not.")
        lines.append("# Review every path before you type DELETE.")
        lines.append("set -euo pipefail")
        lines.append("printf 'Type DELETE to continue: '")
        lines.append("read -r answer")
        lines.append("if [[ \"$answer\" != \"DELETE\" ]]; then")
        lines.append("  echo \"Cancelled.\"")
        lines.append("  exit 1")
        lines.append("fi")
        lines.append("trash_path() {")
        lines.append("  osascript - \"$@\" <<'APPLESCRIPT'")
        lines.append("on run argv")
        lines.append("  tell application \"Finder\" to delete (POSIX file (item 1 of argv) as alias)")
        lines.append("end run")
        lines.append("APPLESCRIPT")
        lines.append("}")
        if vetted.allowed.isEmpty {
            lines.append("echo \"Nothing in this plan was allowed.\"")
            lines.append("exit 1")
        }
        for item in vetted.allowed {
            lines.append("echo \(shellQuote(item.title))")
            switch item.method {
            case .trash:
                lines.append("trash_path \(shellQuote(SecurityGate.standardized(item.payload)))")
            case .simctlRuntime:
                lines.append("xcrun simctl runtime delete \(shellQuote(item.payload))")
            case .simctlUnavailable:
                lines.append("xcrun simctl delete unavailable")
            case .dockerImage:
                lines.append("docker image rm \(shellQuote(item.payload))")
            }
        }
        for (item, reason) in vetted.rejected {
            lines.append("# skipped \(shellQuote(item.title)): \(reason)")
        }
        lines.append("echo Done.")
        return lines.joined(separator: "\n") + "\n"
    }

    public static func shellQuote(_ raw: String) -> String {
        "'" + raw.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func reason(for item: BinItem, home: String) -> String? {
        switch item.kind {
        case .cache:
            guard item.method == .trash else { return "Caches are moved to the Trash." }
            if let reason = SecurityGate.denyReason(item.payload) { return reason }
            if Classifier.rule(for: item.payload, home: home) == nil {
                return "No cleanup rule matches this path."
            }
            return nil
        case .osImage:
            switch item.method {
            case .simctlRuntime:
                return SecurityGate.validRuntimeIdentifier(item.payload) ? nil : "That simulator id is not valid."
            case .simctlUnavailable:
                return item.payload == "unavailable" ? nil : "That simulator action is not valid."
            case .dockerImage:
                return SecurityGate.validDockerID(item.payload) ? nil : "That Docker id is not valid."
            case .trash:
                return SecurityGate.osImageTrashReason(item.payload, home: home)
            }
        case .duplicateFile:
            guard item.method == .trash else { return "Duplicates are moved to the Trash." }
            if item.expectedHash == nil || (item.expectedHash?.count ?? 0) < 64 {
                return "A duplicate needs a hash so the file can be checked again."
            }
            return SecurityGate.duplicateFileReason(item.payload)
        case .appBundle:
            guard item.method == .trash else { return "Apps are moved to the Trash." }
            return SecurityGate.appBundleReason(item.payload, bundleID: item.bundleID ?? "", home: home)
        case .appLeftover:
            guard item.method == .trash else { return "Leftovers are moved to the Trash." }
            return SecurityGate.leftoverReason(item.payload, bundleID: item.bundleID ?? "", home: home)
        }
    }
}

public enum CleanupRunner {
    /// Moves allowed items to the Trash, or calls simctl/docker for image ids.
    /// Call this only after the person has confirmed the list.
    public static func perform(_ items: [BinItem], home: String) -> [RemovalOutcome] {
        let vetted = CleanupPlan.vet(items, home: home)
        var outcomes: [RemovalOutcome] = []
        for (item, reason) in vetted.rejected {
            outcomes.append(RemovalOutcome(title: item.title, payload: item.payload, ok: false, message: reason))
        }
        for item in vetted.allowed {
            outcomes.append(execute(item, home: home))
        }
        return outcomes
    }

    private static func execute(_ item: BinItem, home: String) -> RemovalOutcome {
        if let reason = CleanupPlan.reason(for: item, home: home) {
            return RemovalOutcome(title: item.title, payload: item.payload, ok: false, message: reason)
        }
        switch item.method {
        case .trash:
            return trash(item, home: home)
        case .simctlRuntime:
            let result = Shell.run("/usr/bin/xcrun", arguments: ["simctl", "runtime", "delete", item.payload], timeout: 120)
            return commandOutcome(item, result, success: "Removed the simulator runtime. Trash does not have a copy.")
        case .simctlUnavailable:
            let result = Shell.run("/usr/bin/xcrun", arguments: ["simctl", "delete", "unavailable"], timeout: 120)
            return commandOutcome(item, result, success: "Removed unavailable simulators.")
        case .dockerImage:
            guard let docker = Shell.which("docker") else {
                return RemovalOutcome(title: item.title, payload: item.payload, ok: false, message: "Docker isn't installed.")
            }
            let result = Shell.run(docker, arguments: ["image", "rm", item.payload], timeout: 120)
            return commandOutcome(item, result, success: "Removed the Docker image.")
        }
    }

    private static func trash(_ item: BinItem, home: String) -> RemovalOutcome {
        let url = URL(fileURLWithPath: item.payload).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return RemovalOutcome(title: item.title, payload: item.payload, ok: false, message: "Already gone.")
        }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        if let reason = recheck(item, resolved: resolved, home: home) {
            return RemovalOutcome(title: item.title, payload: item.payload, ok: false, message: reason)
        }
        if item.kind == .duplicateFile {
            guard let expected = item.expectedHash else {
                return RemovalOutcome(title: item.title, payload: item.payload, ok: false, message: "Missing hash.")
            }
            do {
                let digest = try FileHash.sha256(of: url)
                if digest != expected {
                    return RemovalOutcome(title: item.title, payload: item.payload, ok: false, message: "The file changed. Left it in place.")
                }
            } catch {
                return RemovalOutcome(title: item.title, payload: item.payload, ok: false, message: "Could not re-check the file. Left it in place.")
            }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return RemovalOutcome(title: item.title, payload: item.payload, ok: false, message: "Duplicates are files, not folders.")
            }
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return RemovalOutcome(title: item.title, payload: item.payload, ok: true, message: "Moved to the Trash.")
        } catch {
            return RemovalOutcome(title: item.title, payload: item.payload, ok: false, message: error.localizedDescription)
        }
    }

    private static func recheck(_ item: BinItem, resolved: String, home: String) -> String? {
        switch item.kind {
        case .cache:
            return SecurityGate.denyReason(resolved) ?? (Classifier.rule(for: resolved, home: home) == nil ? "No cleanup rule matches the resolved path." : nil)
        case .osImage:
            return SecurityGate.osImageTrashReason(resolved, home: home)
        case .duplicateFile:
            return SecurityGate.duplicateFileReason(resolved)
        case .appBundle:
            return SecurityGate.appBundleReason(resolved, bundleID: item.bundleID ?? "", home: home)
        case .appLeftover:
            return SecurityGate.leftoverReason(resolved, bundleID: item.bundleID ?? "", home: home)
        }
    }

    private static func commandOutcome(_ item: BinItem, _ result: ShellResult, success: String) -> RemovalOutcome {
        if result.code == 0 {
            return RemovalOutcome(title: item.title, payload: item.payload, ok: true, message: success)
        }
        let detail = result.error.isEmpty ? result.output : result.error
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return RemovalOutcome(
            title: item.title,
            payload: item.payload,
            ok: false,
            message: trimmed.isEmpty ? "The command failed." : trimmed
        )
    }
}
