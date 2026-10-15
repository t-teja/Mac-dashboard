import Foundation

public enum OSImageScanner {
    /// Read-only. Docker is included only when `includeDocker` is true, so opening the page does not start the daemon.
    public static func scan(home: String, includeDocker: Bool) -> OSImageReport {
        var items: [OSImageItem] = []
        var notes: [String] = []
        let home = SecurityGate.standardized(home)

        let runtimes = Shell.run("/usr/bin/xcrun", arguments: ["simctl", "runtime", "list", "-j"], timeout: 25)
        if runtimes.code == 0 {
            items.append(contentsOf: parseRuntimes(runtimes.output))
        } else if runtimes.error.contains("unable to find utility") || runtimes.code == 127 {
            notes.append("Xcode's simulator tools aren't available, so iOS runtimes aren't listed.")
        }

        let devices = Shell.run("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "unavailable", "-j"], timeout: 25)
        if devices.code == 0 {
            let unavailable = unavailableDeviceCount(devices.output)
            if unavailable > 0 {
                items.append(OSImageItem(
                    id: "sim-unavailable",
                    title: "Unavailable simulators",
                    subtitle: "\(unavailable) devices whose runtime is already gone",
                    bytes: 0,
                    kind: .appleDevices,
                    method: .simctlUnavailable,
                    payload: "unavailable"
                ))
            }
        }

        items.append(contentsOf: androidImages(home: home))
        items.append(contentsOf: macInstallers(home: home))

        if includeDocker {
            if let docker = Shell.which("docker") {
                let listed = Shell.run(docker, arguments: ["images", "--format", "{{json .}}"], timeout: 20)
                if listed.code == 0 {
                    items.append(contentsOf: parseDocker(listed.output))
                } else {
                    notes.append("Docker didn't answer. Images stay unlisted until the daemon is running.")
                }
            } else {
                notes.append("Docker isn't installed.")
            }
        }

        return OSImageReport(
            items: items.sorted { $0.bytes > $1.bytes },
            notes: notes
        )
    }

    private static func parseRuntimes(_ output: String) -> [OSImageItem] {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let rows: [[String: Any]]
        if let list = json as? [[String: Any]] {
            rows = list
        } else if let object = json as? [String: Any], let list = object["runtimes"] as? [[String: Any]] {
            rows = list
        } else {
            return []
        }
        return rows.compactMap { row in
            let identifier = (row["identifier"] as? String)
                ?? (row["runtimeIdentifier"] as? String)
                ?? (row["bundlePath"] as? String)
            guard let identifier, SecurityGate.validRuntimeIdentifier(identifier) else { return nil }
            let platform = (row["platform"] as? String) ?? "Simulator"
            let version = (row["version"] as? String) ?? ""
            let bytes = int64(row["sizeBytes"]) ?? int64(row["size"]) ?? 0
            let title = [platform, version].filter { !$0.isEmpty }.joined(separator: " ")
            return OSImageItem(
                id: "runtime-" + identifier,
                title: title.isEmpty ? identifier : title,
                subtitle: identifier,
                bytes: bytes,
                kind: .appleSimulator,
                method: .simctlRuntime,
                payload: identifier
            )
        }
    }

    private static func unavailableDeviceCount(_ output: String) -> Int {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: Any] else { return 0 }
        var count = 0
        for value in devices.values {
            if let list = value as? [Any] { count += list.count }
        }
        return count
    }

    private static func androidImages(home: String) -> [OSImageItem] {
        let root = URL(fileURLWithPath: home).appendingPathComponent("Library/Android/sdk/system-images")
        guard let apis = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        var items: [OSImageItem] = []
        for api in apis where isDirectory(api) {
            guard let types = try? FileManager.default.contentsOfDirectory(at: api, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for type in types where isDirectory(type) {
                guard let abis = try? FileManager.default.contentsOfDirectory(at: type, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
                for abi in abis where isDirectory(abi) {
                    let path = abi.path
                    guard SecurityGate.osImageTrashReason(path, home: home) == nil else { continue }
                    let summed = DirectorySize.allocated(abi)
                    items.append(OSImageItem(
                        id: "android-" + path,
                        title: "\(api.lastPathComponent) \(type.lastPathComponent)",
                        subtitle: path,
                        bytes: summed,
                        kind: .androidSystem,
                        method: .trash,
                        payload: path
                    ))
                }
            }
        }
        return items
    }

    private static func macInstallers(home: String) -> [OSImageItem] {
        let parents = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: home).appendingPathComponent("Applications"),
            URL(fileURLWithPath: home).appendingPathComponent("Downloads"),
            URL(fileURLWithPath: home).appendingPathComponent("Desktop")
        ]
        var items: [OSImageItem] = []
        for parent in parents {
            guard let entries = try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                continue
            }
            for entry in entries {
                let path = entry.path
                guard SecurityGate.osImageTrashReason(path, home: home) == nil else { continue }
                let bytes = entry.pathExtension.lowercased() == "app" ? DirectorySize.allocated(entry) : (try? entry.resourceValues(forKeys: [.fileAllocatedSizeKey]).fileAllocatedSize).map(Int64.init) ?? 0
                items.append(OSImageItem(
                    id: "installer-" + path,
                    title: entry.lastPathComponent,
                    subtitle: path,
                    bytes: Int64(bytes),
                    kind: .macInstaller,
                    method: .trash,
                    payload: path
                ))
            }
        }
        return items
    }

    private static func parseDocker(_ output: String) -> [OSImageItem] {
        output.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8),
                  let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let id = (row["ID"] as? String) ?? (row["id"] as? String) ?? ""
            guard SecurityGate.validDockerID(id) else { return nil }
            let repository = (row["Repository"] as? String) ?? "image"
            let tag = (row["Tag"] as? String) ?? ""
            let sizeText = (row["Size"] as? String) ?? "0"
            let title = tag.isEmpty || tag == "<none>" ? repository : "\(repository):\(tag)"
            return OSImageItem(
                id: "docker-" + id,
                title: title,
                subtitle: id,
                bytes: parseHuman(sizeText),
                kind: .docker,
                method: .dockerImage,
                payload: id
            )
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }

    private static func parseHuman(_ raw: String) -> Int64 {
        let text = raw.trimmingCharacters(in: .whitespaces).uppercased()
        let numberText = text.prefix { $0.isNumber || $0 == "." }
        let number = Double(numberText) ?? 0
        if text.contains("GB") { return Int64(number * 1_000_000_000) }
        if text.contains("MB") { return Int64(number * 1_000_000) }
        if text.contains("KB") { return Int64(number * 1_000) }
        return Int64(number)
    }
}

enum DirectorySize {
    static func allocated(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileAllocatedSizeKey, .isSymbolicLinkKey, .isRegularFileKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileAllocatedSizeKey])
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values?.isRegularFile == true {
                total += Int64(values?.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
