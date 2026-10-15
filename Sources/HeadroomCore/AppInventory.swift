import Foundation

public enum AppInventory {
    public static func load(home: String) -> [InstalledApp] {
        let home = SecurityGate.standardized(home)
        let folders = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: home).appendingPathComponent("Applications")
        ]
        var apps: [InstalledApp] = []
        for folder in folders {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries where entry.pathExtension == "app" {
                guard let app = describe(entry, home: home) else { continue }
                apps.append(app)
            }
        }
        return apps.sorted { $0.bytes > $1.bytes }
    }

    private static func describe(_ url: URL, home: String) -> InstalledApp? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let info = object as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String,
              SecurityGate.isSafeBundleID(bundleID),
              !bundleID.hasPrefix("com.apple.") else { return nil }
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let bytes = DirectorySize.allocated(url)
        let leftovers = findLeftovers(bundleID: bundleID, appName: name, home: home)
        return InstalledApp(name: name, bundleID: bundleID, path: url.path, bytes: bytes, leftovers: leftovers)
    }

    private static func findLeftovers(bundleID: String, appName: String, home: String) -> [Leftover] {
        _ = appName
        let paths = SecurityGate.leftoverPaths(bundleID: bundleID, home: home)
        var leftovers: [Leftover] = []
        for path in paths {
            guard SecurityGate.leftoverReason(path, bundleID: bundleID, home: home) == nil else { continue }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            let bytes: Int64
            if isDir.boolValue {
                bytes = DirectorySize.allocated(URL(fileURLWithPath: path))
            } else {
                let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileAllocatedSizeKey])
                bytes = Int64(values?.fileAllocatedSize ?? 0)
            }
            let kind = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
            leftovers.append(Leftover(path: path, bytes: bytes, kind: kind))
        }
        return leftovers
    }
}
