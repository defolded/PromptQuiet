import AppKit
@preconcurrency import CoreFoundation
import Foundation
import os
import PromptQuietCore

/// Dynamically suppresses macOS Dock icon attention-bouncing (`no-bouncing`) only while
/// notifications are paused, and restores normal Dock bouncing when notifications resume.
enum DockBounceController {
    private nonisolated static let dockDomain = "com.apple.dock"
    private nonisolated static let noBouncingKey = "no-bouncing"
    private nonisolated static let activeLock = OSAllocatedUnfairLock<Bool>(initialState: false)

    private nonisolated static var lockFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("PromptQuiet", isDirectory: true)
            .appendingPathComponent("dock_nobounce.lock", isDirectory: false)
    }

    nonisolated static func isDockNoBouncingSet() -> Bool {
        (CFPreferencesCopyAppValue(noBouncingKey as CFString, dockDomain as CFString) as? Bool) == true
    }

    @MainActor
    static func migrateAndRestoreStartupIfNeeded(settings: inout PromptQuietSettings) -> Bool {
        var didMigrate = false
        let lockExists = FileManager.default.fileExists(atPath: lockFileURL.path)

        if isDockNoBouncingSet() {
            if !lockExists {
                settings.suppressDockBouncing = true
                didMigrate = true
            }
            applyDockNoBouncing(nil)
        } else if lockExists {
            removeLockFile()
        }

        return didMigrate
    }

    @MainActor
    static func suppressIfNeeded(enabled: Bool) {
        guard enabled else {
            restoreIfNeeded()
            return
        }

        let alreadyActive = activeLock.withLock { current -> Bool in
            if current { return true }
            current = true
            return false
        }
        guard !alreadyActive else { return }

        writeLockFile()
        applyDockNoBouncing(kCFBooleanTrue)
    }

    @MainActor
    static func restoreIfNeeded() {
        emergencyRestoreSync()
    }

    nonisolated static func emergencyRestoreSync() {
        let wasActive = activeLock.withLock { current -> Bool in
            let previous = current
            current = false
            return previous
        }
        let lockExists = FileManager.default.fileExists(atPath: lockFileURL.path)
        guard wasActive || lockExists else { return }

        applyDockNoBouncing(nil)
    }

    private nonisolated static func applyDockNoBouncing(_ value: CFBoolean?) {
        CFPreferencesSetAppValue(noBouncingKey as CFString, value, dockDomain as CFString)
        CFPreferencesAppSynchronize(dockDomain as CFString)

        if value == nil {
            removeLockFile()
        }

        if let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
            dockApp.terminate()
        }
    }

    private nonisolated static func writeLockFile() {
        let url = lockFileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "1".write(to: url, atomically: true, encoding: .utf8)
    }

    private nonisolated static func removeLockFile() {
        try? FileManager.default.removeItem(at: lockFileURL)
    }
}
