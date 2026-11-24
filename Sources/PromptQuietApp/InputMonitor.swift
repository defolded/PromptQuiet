import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import PromptQuietCore

private final class EventTapContext: @unchecked Sendable {
    var machPort: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    let handler: @Sendable (KeyAction, UInt16) -> Void

    init(handler: @escaping @Sendable (KeyAction, UInt16) -> Void) {
        self.handler = handler
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let context = Unmanaged<EventTapContext>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = context.machPort {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags
    var modifiers: KeyModifiers = []
    if flags.contains(.maskShift) { modifiers.insert(.shift) }
    if flags.contains(.maskCommand) { modifiers.insert(.command) }
    if flags.contains(.maskControl) { modifiers.insert(.control) }
    if flags.contains(.maskAlternate) { modifiers.insert(.option) }
    let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

    let action = KeyClassifier.classify(
        keyCode: keyCode,
        modifiers: modifiers,
        isAutoRepeat: isAutoRepeat
    )

    if action != .ignored {
        context.handler(action, keyCode)
    }

    return Unmanaged.passUnretained(event)
}

/// Monitors the frontmost application and observes key-down actions via `CGEventTap`
/// (`.defaultTap` under Accessibility or `.listenOnly` under Input Monitoring) plus an
/// `NSEvent` global keyDown fallback with timestamp deduplication. Never modifies events or reads text.
@MainActor
final class InputMonitor {
    var onKeyAction: ((KeyAction, RunningAppInfo) -> Void)?
    var onFrontmostAppChanged: ((RunningAppInfo) -> Void)?
    var onAccessibilityChanged: ((Bool) -> Void)?
    var onEventTapStateChanged: ((Bool) -> Void)?

    private(set) var isAccessibilityTrusted: Bool = AXIsProcessTrusted() || CGPreflightListenEventAccess()
    private(set) var isEventTapRunning: Bool = false
    private(set) var currentFrontmostApp: RunningAppInfo

    private var tapContext: EventTapContext?
    private var retainedContextPointer: UnsafeMutableRawPointer?
    private var tapModeListenOnly: Bool?
    private var globalKeyMonitor: Any?
    private var trustPollTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?

    private var lastDeliveredKeyCode: UInt16?
    private var lastDeliveredAction: KeyAction?
    private var lastDeliveredTime: TimeInterval = 0

    init() {
        let app = NSWorkspace.shared.frontmostApplication
        self.currentFrontmostApp = RunningAppInfo(
            bundleIdentifier: app?.bundleIdentifier,
            localizedName: app?.localizedName
        )
    }

    func start() {
        if workspaceObserver == nil {
            workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let runningApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let info = RunningAppInfo(
                    bundleIdentifier: runningApp?.bundleIdentifier,
                    localizedName: runningApp?.localizedName
                )
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.currentFrontmostApp = info
                    self.onFrontmostAppChanged?(info)
                    self.refreshAccessibilityAndTap()
                }
            }
        }

        refreshAccessibilityAndTap()
    }

    func stop() {
        trustPollTimer?.invalidate()
        trustPollTimer = nil

        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }

        stopTap()
        stopGlobalMonitor()
    }

    func requestAccessibilityPermission() {
        // Use the literal key string to avoid Swift 6 concurrency diagnostics on global CFString vars.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        refreshAccessibilityAndTap()
        ensureTrustPolling()
    }

    func resetAndRequestAccessibilityPermission() {
        let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        if FileManager.default.isExecutableFile(atPath: lsregisterPath) {
            let lsProcess = Process()
            lsProcess.executableURL = URL(fileURLWithPath: lsregisterPath)
            lsProcess.arguments = ["-f", Bundle.main.bundlePath]
            try? lsProcess.run()
            lsProcess.waitUntilExit()
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "com.promptquiet.app"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "All", bundleID]
        try? process.run()
        process.waitUntilExit()

        requestAccessibilityPermission()
    }

    func refreshAccessibilityAndTap() {
        let axTrusted = AXIsProcessTrusted()
        let listenTrusted = CGPreflightListenEventAccess()
        let trusted = axTrusted || listenTrusted

        if axTrusted {
            if !isEventTapRunning || tapModeListenOnly == true {
                stopTap()
                startTap(listenOnly: false)
            }
            startGlobalMonitor()
        } else if listenTrusted {
            stopGlobalMonitor()
            if !isEventTapRunning || tapModeListenOnly == false {
                stopTap()
                startTap(listenOnly: true)
            }
        } else {
            stopTap()
            stopGlobalMonitor()
        }

        isAccessibilityTrusted = trusted
        onAccessibilityChanged?(trusted)

        if trusted && (isEventTapRunning || globalKeyMonitor != nil) {
            trustPollTimer?.invalidate()
            trustPollTimer = nil
        } else {
            ensureTrustPolling()
        }
    }

    private func deliverAction(_ action: KeyAction, keyCode: UInt16) {
        let now = ProcessInfo.processInfo.systemUptime
        if lastDeliveredKeyCode == keyCode,
           lastDeliveredAction == action,
           (now - lastDeliveredTime) < 0.025 {
            return
        }
        lastDeliveredKeyCode = keyCode
        lastDeliveredAction = action
        lastDeliveredTime = now

        onKeyAction?(action, currentFrontmostApp)
    }

    private func ensureTrustPolling() {
        guard trustPollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAccessibilityAndTap()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trustPollTimer = timer
    }

    private func startTap(listenOnly: Bool) {
        guard !isEventTapRunning else { return }

        let context = EventTapContext { [weak self] action, keyCode in
            Task { @MainActor [weak self] in
                self?.deliverAction(action, keyCode: keyCode)
            }
        }

        let pointer = Unmanaged.passRetained(context).toOpaque()
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: listenOnly ? .listenOnly : .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: pointer
        ) else {
            Unmanaged<EventTapContext>.fromOpaque(pointer).release()
            isEventTapRunning = false
            tapModeListenOnly = nil
            onEventTapStateChanged?(false)
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            Unmanaged<EventTapContext>.fromOpaque(pointer).release()
            isEventTapRunning = false
            tapModeListenOnly = nil
            onEventTapStateChanged?(false)
            return
        }

        context.machPort = port
        context.runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        self.tapContext = context
        self.retainedContextPointer = pointer
        self.tapModeListenOnly = listenOnly
        self.isEventTapRunning = true
        onEventTapStateChanged?(true)
    }

    private func stopTap() {
        if let source = tapContext?.runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let port = tapContext?.machPort {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let pointer = retainedContextPointer {
            Unmanaged<EventTapContext>.fromOpaque(pointer).release()
            retainedContextPointer = nil
        }

        tapContext = nil
        tapModeListenOnly = nil
        if isEventTapRunning {
            isEventTapRunning = false
            onEventTapStateChanged?(false)
        }
    }

    private func startGlobalMonitor() {
        guard globalKeyMonitor == nil else { return }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            var modifiers: KeyModifiers = []
            if flags.contains(.shift) { modifiers.insert(.shift) }
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.option) { modifiers.insert(.option) }
            let isAutoRepeat = event.isARepeat

            let action = KeyClassifier.classify(
                keyCode: keyCode,
                modifiers: modifiers,
                isAutoRepeat: isAutoRepeat
            )
            guard action != .ignored else { return }

            Task { @MainActor [weak self] in
                self?.deliverAction(action, keyCode: keyCode)
            }
        }
    }

    private func stopGlobalMonitor() {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }
}
