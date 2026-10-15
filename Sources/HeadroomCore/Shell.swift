import Foundation

public struct ShellResult: Sendable, Equatable {
    public var code: Int32
    public var output: String
    public var error: String

    public init(code: Int32, output: String, error: String) {
        self.code = code
        self.output = output
        self.error = error
    }
}

public enum Shell {
    /// Runs an executable directly. There is no shell, so arguments are not expanded.
    public static func run(_ launchPath: String, arguments: [String], timeout: TimeInterval = 20) -> ShellResult {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else {
            return ShellResult(code: 127, output: "", error: "Missing \(launchPath)")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return ShellResult(code: 127, output: "", error: error.localizedDescription)
        }

        let outputBox = PipeBox()
        let errorBox = PipeBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outputBox.data = out.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errorBox.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            _ = group.wait(timeout: .now() + 2)
            return ShellResult(code: 124, output: "", error: "Timed out")
        }
        group.wait()
        let output = String(data: outputBox.data, encoding: .utf8) ?? ""
        let error = String(data: errorBox.data, encoding: .utf8) ?? ""
        return ShellResult(code: process.terminationStatus, output: output, error: error)
    }

    public static func which(_ name: String) -> String? {
        let result = run("/usr/bin/which", arguments: [name], timeout: 5)
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.code == 0, path.hasPrefix("/") else { return nil }
        return path
    }
}

private final class PipeBox: @unchecked Sendable {
    var data = Data()
}
