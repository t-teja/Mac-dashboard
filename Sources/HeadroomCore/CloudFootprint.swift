import Foundation

public enum CloudFootprint {
    /// Names the local cloud folders. Sizing is separate so merely opening the page never walks iCloud.
    public static func places(home: String) -> [CloudPlace] {
        let home = SecurityGate.standardized(home)
        var places: [CloudPlace] = []
        let iCloud = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: iCloud.path) {
            places.append(CloudPlace(
                provider: "iCloud Drive",
                path: iCloud.path,
                localBytes: nil,
                note: "This is the copy on this Mac, not your iCloud plan."
            ))
        }
        let storage = URL(fileURLWithPath: home).appendingPathComponent("Library/CloudStorage")
        if let entries = try? FileManager.default.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for entry in entries {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else { continue }
                places.append(CloudPlace(
                    provider: providerName(entry.lastPathComponent),
                    path: entry.path,
                    localBytes: nil,
                    note: "Local files only. Nothing here is deleted from the desk."
                ))
            }
        }
        let driveFS = URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/Google/DriveFS")
        if FileManager.default.fileExists(atPath: driveFS.path) {
            places.append(CloudPlace(
                provider: "Google Drive cache",
                path: driveFS.path,
                localBytes: nil,
                note: "Drive's local cache. This is not your Google quota."
            ))
        }
        return places
    }

    /// Sums allocated bytes only. File contents are never read, so placeholders are not downloaded.
    public static func measure(_ place: CloudPlace) -> CloudPlace {
        var copy = place
        copy.localBytes = DirectorySize.allocated(URL(fileURLWithPath: place.path))
        return copy
    }

    private static func providerName(_ folder: String) -> String {
        let lower = folder.lowercased()
        if lower.contains("icloud") { return "iCloud" }
        if lower.contains("googledrive") { return "Google Drive" }
        if lower.contains("dropbox") { return "Dropbox" }
        if lower.contains("onedrive") { return "OneDrive" }
        return folder
    }
}
