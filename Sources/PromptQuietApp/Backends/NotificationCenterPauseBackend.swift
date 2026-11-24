import AppKit
import Darwin
import Foundation
import os

enum NotificationCenterPauseError: LocalizedError {
    case processNotFound
    case signalFailed(pid: pid_t, errnoValue: Int32)

    var errorDescription: String? {
        switch self {
        case .processNotFound:
            return "Could not locate running NotificationCenter process."
        case .signalFailed(let pid, let errnoValue):
            let message = String(cString: strerror(errnoValue))
            return "Failed to signal NotificationCenter (pid \(pid)): \(message)."
        }
    }
}

/// Suspends and resumes `NotificationCenter` (`com.apple.notificationcenterui`) via SIGSTOP/SIGCONT
/// with a persistent crash-recovery lock file so Notification Center never remains frozen.
@MainActor
final class NotificationCenterPauseBackend: NotificationSuppressor {
    private nonisolated static let bundleIdentifier = "com.apple.notificationcenterui"
    private nonisolated static let stoppedPIDsLock = OSAllocatedUnfairLock<Set<pid_t>>(initialState: [])

    private nonisolated static var lockFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("PromptQuiet", isDirectory: true)
            .appendingPathComponent("sigstop.lock", isDirectory: false)
    }

    private(set) var statusDetail: String?

    var isActive: Bool {
        Self.stoppedPIDsLock.withLock { !$0.isEmpty }
    }

    func suppress() async throws {
        if isActive {
            return
        }

        let pids = Self.runningNotificationCenterPIDs()
        guard !pids.isEmpty else {
            statusDetail = NotificationCenterPauseError.processNotFound.errorDescription
            throw NotificationCenterPauseError.processNotFound
        }

        Self.writeLockFile(pids: pids)
        var stoppedSoFar: [pid_t] = []

        for pid in pids {
            _ = Self.stoppedPIDsLock.withLock { $0.insert(pid) }
            if Darwin.kill(pid, SIGSTOP) != 0 {
                let err = errno
                for rollbackPID in stoppedSoFar {
                    _ = Darwin.kill(rollbackPID, SIGCONT)
                }
                Self.stoppedPIDsLock.withLock { $0.removeAll() }
                Self.removeLockFile()
                let error = NotificationCenterPauseError.signalFailed(pid: pid, errnoValue: err)
                statusDetail = error.errorDescription
                throw error
            }
            stoppedSoFar.append(pid)
        }

        statusDetail = nil
    }

    func resume() async {
        emergencyResumeSync()
    }

    func emergencyResumeSync() {
        Self.resumeAllNotificationCenterProcesses()
        statusDetail = nil
    }

    /// Sends SIGCONT to any previously frozen `NotificationCenter` process if a prior run crashed.
    nonisolated static func recoverIfPreviouslyCrashed() {
        guard FileManager.default.fileExists(atPath: lockFileURL.path) else {
            return
        }
        resumeAllNotificationCenterProcesses()
    }

    /// Unconditionally resumes all tracked, lock-file, and running NotificationCenter PIDs.
    nonisolated static func resumeAllNotificationCenterProcesses() {
        var pids = stoppedPIDsLock.withLock { current -> Set<pid_t> in
            let copy = current
            current.removeAll()
            return copy
        }

        for pid in readLockFilePIDs() {
            pids.insert(pid)
        }
        for pid in runningNotificationCenterPIDs() {
            pids.insert(pid)
        }

        for pid in pids where pid > 0 {
            _ = Darwin.kill(pid, SIGCONT)
        }

        removeLockFile()
    }

    private nonisolated static func runningNotificationCenterPIDs() -> [pid_t] {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .map(\.processIdentifier)
            .filter { $0 > 0 }
    }

    private nonisolated static func writeLockFile(pids: [pid_t]) {
        let url = lockFileURL
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = pids.map(String.init).joined(separator: "\n")
        try? payload.write(to: url, atomically: true, encoding: .utf8)
    }

    private nonisolated static func readLockFilePIDs() -> [pid_t] {
        guard let content = try? String(contentsOf: lockFileURL, encoding: .utf8) else {
            return []
        }
        return content
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 > 0 }
    }

    private nonisolated static func removeLockFile() {
        try? FileManager.default.removeItem(at: lockFileURL)
    }
}
