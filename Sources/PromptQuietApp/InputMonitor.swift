import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import PromptQuietCore

private final class EventTapContext: @unchecked Sendable {
    var machPort: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    let handler: @Sendable (KeyAction) -> Void

    init(handler: @escaping @Sendable (KeyAction) -> Void) {
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
        context.handler(action)
    }

    return Unmanaged.passUnretained(event)
}

/// Monitors the frontmost application and listens for key-down actions via a `.listenOnly` CGEventTap.
/// Only virtual key codes and modifier flags are inspected; typed characters are never read or stored.
@MainActor
final class InputMonitor {
    var onKeyAction: ((KeyAction, RunningAppInfo) -> Void)?
    var onFrontmostAppChanged: ((RunningAppInfo) -> Void)?
    var onAccessibilityChanged: ((Bool) -> Void)?
    var onEventTapStateChanged: ((Bool) -> Void)?

    private(set) var isAccessibilityTrusted: Bool = AXIsProcessTrusted()
    private(set) var isEventTapRunning: Bool = false
    private(set) var currentFrontmostApp: RunningAppInfo

    private var tapContext: EventTapContext?
    private var retainedContextPointer: UnsafeMutableRawPointer?
    private var trustPollTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?

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
    }

    func requestAccessibilityPermission() {
        // Use the literal key string to avoid Swift 6 concurrency diagnostics on global CFString vars.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshAccessibilityAndTap()
        ensureTrustPolling()
    }

    func refreshAccessibilityAndTap() {
        let trusted = AXIsProcessTrusted()
        if trusted != isAccessibilityTrusted {
            isAccessibilityTrusted = trusted
            onAccessibilityChanged?(trusted)
        } else {
            onAccessibilityChanged?(trusted)
        }

        if trusted {
            if !isEventTapRunning {
                startTap()
            }
            if isEventTapRunning {
                trustPollTimer?.invalidate()
                trustPollTimer = nil
            } else {
                ensureTrustPolling()
            }
        } else {
            stopTap()
            ensureTrustPolling()
        }
    }

    private func ensureTrustPolling() {
        guard trustPollTimer == nil else { return }
        trustPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAccessibilityAndTap()
            }
        }
    }

    private func startTap() {
        guard !isEventTapRunning else { return }

        let context = EventTapContext { [weak self] action in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onKeyAction?(action, self.currentFrontmostApp)
            }
        }

        let pointer = Unmanaged.passRetained(context).toOpaque()
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: pointer
        ) else {
            Unmanaged<EventTapContext>.fromOpaque(pointer).release()
            isEventTapRunning = false
            onEventTapStateChanged?(false)
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            Unmanaged<EventTapContext>.fromOpaque(pointer).release()
            isEventTapRunning = false
            onEventTapStateChanged?(false)
            return
        }

        context.machPort = port
        context.runLoopSource = source

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        self.tapContext = context
        self.retainedContextPointer = pointer
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
        if isEventTapRunning {
            isEventTapRunning = false
            onEventTapStateChanged?(false)
        }
    }
}
