import AppKit
import CoreFoundation
import Foundation

/// Toggles macOS Dock's `no-bouncing` preference so background apps stop bouncing vertically
/// without freezing `Dock` (preserving Spaces, Mission Control, and `Cmd+Tab`).
@MainActor
enum DockBounceController {
    private static let dockDomain = "com.apple.dock" as CFString
    private static let noBouncingKey = "no-bouncing" as CFString

    static func isNoBouncingEnabled() -> Bool {
        CFPreferencesCopyAppValue(noBouncingKey, dockDomain) as? Bool ?? false
    }

    static func setNoBouncingEnabled(_ enabled: Bool) {
        CFPreferencesSetAppValue(
            noBouncingKey,
            enabled ? kCFBooleanTrue : kCFBooleanFalse,
            dockDomain
        )
        CFPreferencesAppSynchronize(dockDomain)

        if let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
            dockApp.terminate()
        }
    }
}
