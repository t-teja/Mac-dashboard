import Darwin
import Foundation

public enum ProcessControl {
    public static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "sysmond", "configd",
        "notifyd", "distnoted", "Finder", "Dock", "SystemUIServer", "ControlCenter",
        "NotificationCenter", "Spotlight", "coreaudiod", "bluetoothd", "airportd",
        "mds", "mds_stores", "MacSpaceSaver", "Headroom", "cfprefsd", "runningboardd", "logd",
        "UserEventAgent", "trustd", "securityd", "amfid", "coreservicesd",
        "powerd", "thermalmonitord", "login", "kernelmanagerd", "watchdogd",
        "opendirectoryd", "securityd", "syspolicyd", "tccd", "secd"
    ]

    public static func denial(name: String, pid: Int32, uid: UInt32, myPid: Int32, myUid: UInt32) -> String? {
        if pid <= 1 { return "That process is part of the system." }
        if pid == myPid { return "Mac Space Saver will not signal itself." }
        if uid != myUid { return "That process belongs to another user." }
        if protectedNames.contains(name) { return "\(name) stays running." }
        return nil
    }

    public static func perform(_ action: ProcessAction, pid: Int32) -> ProcessControlResult {
        let myPid = ProcessInfo.processInfo.processIdentifier
        let myUid = getuid()
        let identity = identify(pid)
        if let reason = denial(name: identity.name, pid: pid, uid: identity.uid, myPid: myPid, myUid: myUid) {
            return ProcessControlResult(ok: false, message: reason)
        }
        switch action {
        case .quit:
            return signal(pid, SIGTERM, success: "Asked \(identity.name) to quit.")
        case .forceQuit:
            return signal(pid, SIGKILL, success: "Force quit \(identity.name).")
        case .pause:
            return signal(pid, SIGSTOP, success: "Paused \(identity.name).")
        case .resume:
            return signal(pid, SIGCONT, success: "Resumed \(identity.name).")
        case .priorityLow:
            return renice(pid, 19, success: "Lowered the priority of \(identity.name). macOS still won't cap it at a CPU percent.")
        case .priorityNormal:
            return renice(pid, 0, success: "Restored normal priority for \(identity.name).")
        }
    }

    private static func identify(_ pid: Int32) -> (name: String, uid: UInt32) {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        let uid: UInt32
        if size == Int32(MemoryLayout<proc_bsdinfo>.size) {
            uid = info.pbi_uid
        } else {
            uid = UInt32.max
        }
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        let name = length > 0 ? String(cString: buffer) : "pid \(pid)"
        return (name, uid)
    }

    private static func signal(_ pid: Int32, _ signal: Int32, success: String) -> ProcessControlResult {
        if kill(pid, signal) == 0 {
            return ProcessControlResult(ok: true, message: success)
        }
        return ProcessControlResult(ok: false, message: String(cString: strerror(errno)))
    }

    private static func renice(_ pid: Int32, _ value: Int32, success: String) -> ProcessControlResult {
        // Never request a negative nice. That needs root.
        let clamped = max(0, min(19, value))
        errno = 0
        if setpriority(PRIO_PROCESS, id_t(pid), clamped) == 0 || errno == 0 {
            return ProcessControlResult(ok: true, message: success)
        }
        return ProcessControlResult(ok: false, message: String(cString: strerror(errno)))
    }
}
