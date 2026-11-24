import AppKit
import Combine
import Darwin
import Foundation
import PromptQuietCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppController: ObservableObject {
    private static let settingsDefaultsKey = "PromptQuietSettings"

    @Published var settings: PromptQuietSettings
    @Published private(set) var state: SuppressionState = .idle
    @Published private(set) var remainingSeconds: Int?
    @Published private(set) var isAccessibilityTrusted: Bool = false
    @Published private(set) var isEventTapActive: Bool = false
    @Published private(set) var lastObservedExternalApp: RunningAppInfo?
    @Published private(set) var backendError: String?
    @Published var launchAtLogin: Bool = false

    private let pauseBackend = NotificationCenterPauseBackend()
    private let streamBackend = ScreenCaptureStreamBackend()
    private let inputMonitor = InputMonitor()
    private var stateMachine: SuppressionStateMachine
    private var tickTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private var lifecycleObservers: [NSObjectProtocol] = []

    init() {
        NotificationCenterPauseBackend.recoverIfPreviouslyCrashed()

        let loadedSettings = Self.loadSettings()
        self.settings = loadedSettings
        self.stateMachine = SuppressionStateMachine(settings: loadedSettings)
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)

        setupInputMonitor()
        installLifecycleSafetyHooks()
        inputMonitor.start()
    }

    var activeSuppressor: NotificationSuppressor {
        switch settings.suppressionMode {
        case .notificationCenterPause:
            return pauseBackend
        case .screenCaptureStream:
            return streamBackend
        }
    }

    var menuBarSymbolName: String {
        if !isAccessibilityTrusted {
            return "exclamationmark.shield"
        }
        if !settings.isEnabled {
            return "bell"
        }
        switch state {
        case .idle:
            return "bell"
        case .typingPaused, .postSendPaused:
            return "bell.slash.fill"
        case .manuallyPaused:
            return "bell.badge.slash"
        }
    }

    var statusHeadline: String {
        if !settings.isEnabled {
            return "Auto-Pause Off"
        }
        switch state {
        case .idle:
            return isAccessibilityTrusted ? "Monitoring Ready" : "Accessibility Required"
        case .typingPaused(_, let appName):
            if let seconds = remainingSeconds {
                return "Typing in \(appName) — \(seconds)s"
            }
            return "Typing in \(appName)"
        case .postSendPaused(_, let appName):
            if let seconds = remainingSeconds {
                return "Prompt Sent (\(appName)) — \(seconds)s"
            }
            return "Prompt Sent (\(appName))"
        case .manuallyPaused:
            return "Manually Paused"
        }
    }

    var isSuppressing: Bool {
        state != .idle
    }

    var isManuallyPaused: Bool {
        state == .manuallyPaused
    }

    func setEnabled(_ enabled: Bool) {
        var updated = settings
        updated.isEnabled = enabled
        applyUpdatedSettings(updated)
    }

    func setTypingPauseSeconds(_ seconds: Int) {
        var updated = settings
        updated.typingPauseSeconds = seconds
        applyUpdatedSettings(updated)
    }

    func setPostSendPauseSeconds(_ seconds: Int) {
        var updated = settings
        updated.postSendPauseSeconds = seconds
        applyUpdatedSettings(updated)
    }

    func setShowCountdownInMenuBar(_ show: Bool) {
        var updated = settings
        updated.showCountdownInMenuBar = show
        applyUpdatedSettings(updated)
    }

    func setSuppressionMode(_ newMode: SuppressionMode) {
        guard newMode != settings.suppressionMode else { return }
        let oldBackend = activeSuppressor
        let wasSuppressing = stateMachine.isSuppressing

        var updated = settings
        updated.suppressionMode = newMode
        applyUpdatedSettings(updated)

        if wasSuppressing {
            Task { @MainActor [weak self] in
                await oldBackend.resume()
                guard let self, self.stateMachine.isSuppressing else { return }
                await self.activateSuppressionBackend()
            }
        } else {
            backendError = nil
        }
    }

    func toggleBuiltInApp(_ app: BuiltInApp, enabled: Bool) {
        var updated = settings
        if enabled {
            updated.enabledApps.insert(app)
        } else {
            updated.enabledApps.remove(app)
        }
        applyUpdatedSettings(updated)
    }

    func addCustomBundleIdentifier(_ rawIdentifier: String) {
        let trimmed = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = settings
        if !updated.customBundleIdentifiers.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            updated.customBundleIdentifiers.append(trimmed)
            applyUpdatedSettings(updated)
        }
    }

    func removeCustomBundleIdentifier(_ bundleID: String) {
        var updated = settings
        updated.customBundleIdentifiers.removeAll { $0 == bundleID }
        applyUpdatedSettings(updated)
    }

    func toggleManualPause() {
        let shouldPause = (state != .manuallyPaused)
        let effect = stateMachine.setManualPause(shouldPause)
        syncPublishedState(now: Date())
        applyEffect(effect)
    }

    func resumeNow() {
        let effect = stateMachine.resumeNow()
        syncPublishedState(now: Date())
        applyEffect(effect)
    }

    func forceResumeNotificationCenter() {
        _ = stateMachine.resumeNow()
        syncPublishedState(now: Date())
        pauseBackend.emergencyResumeSync()
        Task { @MainActor in
            await streamBackend.resume()
        }
        backendError = nil
    }

    func grantAccessibilityPermission() {
        inputMonitor.requestAccessibilityPermission()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            backendError = nil
        } catch {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            backendError = "Launch at Login failed: \(error.localizedDescription)"
        }
    }

    func quitApp() {
        emergencyResumeAll()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Private

    private func setupInputMonitor() {
        isAccessibilityTrusted = inputMonitor.isAccessibilityTrusted
        isEventTapActive = inputMonitor.isEventTapRunning

        let selfBundleID = Bundle.main.bundleIdentifier
        if let bundleID = inputMonitor.currentFrontmostApp.bundleIdentifier,
           bundleID != selfBundleID {
            lastObservedExternalApp = inputMonitor.currentFrontmostApp
        }

        inputMonitor.onAccessibilityChanged = { [weak self] trusted in
            self?.isAccessibilityTrusted = trusted
        }

        inputMonitor.onEventTapStateChanged = { [weak self] active in
            self?.isEventTapActive = active
        }

        inputMonitor.onFrontmostAppChanged = { [weak self] appInfo in
            guard let self else { return }
            if let bundleID = appInfo.bundleIdentifier,
               bundleID != Bundle.main.bundleIdentifier {
                self.lastObservedExternalApp = appInfo
            }
        }

        inputMonitor.onKeyAction = { [weak self] action, appInfo in
            self?.handleKeyAction(action, appInfo: appInfo)
        }
    }

    private func handleKeyAction(_ action: KeyAction, appInfo: RunningAppInfo) {
        let now = Date()
        let matchedName = AppMatcher.matches(appInfo, settings: settings)
        let effect = stateMachine.handleKeyAction(action, matchedAppName: matchedName, now: now)
        syncPublishedState(now: now)
        applyEffect(effect)
    }

    private func applyUpdatedSettings(_ newSettings: PromptQuietSettings) {
        var normalized = newSettings
        normalized.normalize()
        settings = normalized
        Self.saveSettings(normalized)

        let now = Date()
        let effect = stateMachine.updateSettings(normalized, now: now)
        syncPublishedState(now: now)
        applyEffect(effect)
    }

    private func applyEffect(_ effect: SuppressionEffect) {
        switch effect {
        case .none:
            break
        case .suppress:
            Task { @MainActor [weak self] in
                await self?.activateSuppressionBackend()
            }
        case .resume:
            Task { @MainActor [weak self] in
                await self?.deactivateAllSuppressionBackends()
            }
        }
    }

    private func activateSuppressionBackend() async {
        do {
            try await activeSuppressor.suppress()
            backendError = nil
        } catch {
            backendError = error.localizedDescription
            _ = stateMachine.resumeNow()
            syncPublishedState(now: Date())
        }
    }

    private func deactivateAllSuppressionBackends() async {
        await pauseBackend.resume()
        await streamBackend.resume()
        backendError = nil
    }

    private func syncPublishedState(now: Date) {
        state = stateMachine.state
        remainingSeconds = stateMachine.remainingSeconds(at: now)
        updateTickTimer()
    }

    private func updateTickTimer() {
        switch state {
        case .typingPaused, .postSendPaused:
            if tickTimer == nil {
                tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.handleTick()
                    }
                }
            }
        case .idle, .manuallyPaused:
            tickTimer?.invalidate()
            tickTimer = nil
        }
    }

    private func handleTick() {
        let now = Date()
        let effect = stateMachine.tick(now: now)
        syncPublishedState(now: now)
        applyEffect(effect)
    }

    private func emergencyResumeAll() {
        _ = stateMachine.resumeNow()
        tickTimer?.invalidate()
        tickTimer = nil
        pauseBackend.emergencyResumeSync()
        streamBackend.emergencyResumeSync()
        state = .idle
        remainingSeconds = nil
    }

    private func installLifecycleSafetyHooks() {
        let appWillTerminate = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.emergencyResumeAll()
            }
        }
        lifecycleObservers.append(appWillTerminate)

        let workspaceWillSleep = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.emergencyResumeAll()
            }
        }
        lifecycleObservers.append(workspaceWillSleep)

        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                NotificationCenterPauseBackend.resumeAllNotificationCenterProcesses()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private static func loadSettings() -> PromptQuietSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsDefaultsKey),
              let decoded = try? PromptQuietSettings.decodeJSON(from: data) else {
            return PromptQuietSettings()
        }
        return decoded
    }

    private static func saveSettings(_ settings: PromptQuietSettings) {
        if let data = try? settings.encodeJSON() {
            UserDefaults.standard.set(data, forKey: settingsDefaultsKey)
        }
    }
}
