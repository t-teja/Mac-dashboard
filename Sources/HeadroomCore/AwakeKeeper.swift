import Foundation
import IOKit.pwr_mgt

/// Holds one idle-sleep assertion. The display assertion also keeps the system awake.
/// Releasing it, or quitting the app, lets macOS sleep on its normal schedule.
public final class AwakeKeeper: @unchecked Sendable {
    private let lock = NSLock()
    private var assertion: IOPMAssertionID = 0

    public init() {}

    @discardableResult
    public func update(stayAwake: Bool, keepDisplayOn: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        releaseLocked()
        guard stayAwake else { return true }
        let type = keepDisplayOn
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep
        var created: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Mac Space Saver" as CFString,
            &created
        )
        guard result == kIOReturnSuccess else { return false }
        assertion = created
        return true
    }

    public func release() {
        lock.lock()
        defer { lock.unlock() }
        releaseLocked()
    }

    private func releaseLocked() {
        guard assertion != 0 else { return }
        IOPMAssertionRelease(assertion)
        assertion = 0
    }

    deinit {
        releaseLocked()
    }
}
