import Foundation
import Testing
@testable import PromptQuietCore

@Suite("PromptQuietCore Tests")
struct PromptQuietCoreTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Typing starts 20s pause, extends on subsequent typing, and resumes at expiration")
    func typingPauseAndExtension() {
        var machine = SuppressionStateMachine()

        let startEffect = machine.handleKeyAction(.typing, matchedAppName: "Claude", now: baseDate)
        #expect(startEffect == .suppress)
        #expect(machine.isSuppressing)
        #expect(machine.remainingSeconds(at: baseDate) == 20)

        let t10 = baseDate.addingTimeInterval(10)
        #expect(machine.tick(now: t10) == .none)
        let extendEffect = machine.handleKeyAction(.typing, matchedAppName: "Claude", now: t10)
        #expect(extendEffect == .none)
        #expect(machine.remainingSeconds(at: t10) == 20)

        let t29 = baseDate.addingTimeInterval(29)
        #expect(machine.tick(now: t29) == .none)
        #expect(machine.isSuppressing)
        #expect(machine.remainingSeconds(at: t29) == 1)

        let t30 = baseDate.addingTimeInterval(30)
        #expect(machine.tick(now: t30) == .resume)
        #expect(!machine.isSuppressing)
        #expect(machine.state == .idle)
    }

    @Test("Sending prompt via Return or Cmd+Return switches to 5s post-send pause")
    func promptSentTransitionsToFiveSecondPause() {
        var machine = SuppressionStateMachine()
        #expect(machine.handleKeyAction(.typing, matchedAppName: "Cursor", now: baseDate) == .suppress)

        let t4 = baseDate.addingTimeInterval(4)
        let sendAction = KeyClassifier.classify(keyCode: 36, modifiers: [])
        #expect(sendAction == .promptSent)

        let effect = machine.handleKeyAction(sendAction, matchedAppName: "Cursor", now: t4)
        #expect(effect == .none)
        #expect(machine.remainingSeconds(at: t4) == 5)

        #expect(machine.tick(now: t4.addingTimeInterval(4)) == .none)
        #expect(machine.isSuppressing)
        #expect(machine.tick(now: t4.addingTimeInterval(5)) == .resume)
        #expect(machine.state == .idle)

        // Verify Cmd+Return also classifies as promptSent
        #expect(KeyClassifier.classify(keyCode: 36, modifiers: [.command]) == .promptSent)
        #expect(KeyClassifier.classify(keyCode: 76, modifiers: [.command]) == .promptSent)
    }

    @Test("Shift+Return classifies as typing and keeps 20s pause instead of 5s")
    func shiftReturnStaysTyping() {
        var machine = SuppressionStateMachine()
        #expect(machine.handleKeyAction(.typing, matchedAppName: "Antigravity", now: baseDate) == .suppress)

        let t5 = baseDate.addingTimeInterval(5)
        let newlineAction = KeyClassifier.classify(keyCode: 36, modifiers: [.shift])
        #expect(newlineAction == .typing)

        #expect(machine.handleKeyAction(newlineAction, matchedAppName: "Antigravity", now: t5) == .none)
        if case .typingPaused(let expiresAt, let appName) = machine.state {
            #expect(appName == "Antigravity")
            #expect(expiresAt == t5.addingTimeInterval(20))
        } else {
            Issue.record("Expected .typingPaused after Shift+Return, got \(machine.state)")
        }
    }

    @Test("Typing again during 5s post-send countdown cancels 5s timer and restores 20s pause")
    func typingDuringPostSendRestoresTypingPause() {
        var machine = SuppressionStateMachine()
        #expect(machine.handleKeyAction(.typing, matchedAppName: "Claude", now: baseDate) == .suppress)
        #expect(machine.handleKeyAction(.promptSent, matchedAppName: "Claude", now: baseDate.addingTimeInterval(2)) == .none)

        let t4 = baseDate.addingTimeInterval(4)
        #expect(machine.handleKeyAction(.typing, matchedAppName: "Claude", now: t4) == .none)
        if case .typingPaused(let expiresAt, _) = machine.state {
            #expect(expiresAt == t4.addingTimeInterval(20))
        } else {
            Issue.record("Expected .typingPaused when resuming typing during post-send countdown")
        }
    }

    @Test("Non-editing shortcuts, navigation keys, and non-target apps are ignored; Cmd+V counts as typing")
    func appMatchingAndKeyClassification() {
        let settings = PromptQuietSettings()

        let claude = RunningAppInfo(bundleIdentifier: "com.anthropic.claudefordesktop", localizedName: "Claude")
        let antigravity = RunningAppInfo(bundleIdentifier: "com.google.antigravity", localizedName: "Antigravity")
        let cursor = RunningAppInfo(bundleIdentifier: "com.todesktop.230313mzl4w4u92", localizedName: "Cursor")
        let safari = RunningAppInfo(bundleIdentifier: "com.apple.Safari", localizedName: "Safari")

        #expect(AppMatcher.matches(claude, settings: settings) == "Claude")
        #expect(AppMatcher.matches(antigravity, settings: settings) == "Antigravity")
        #expect(AppMatcher.matches(cursor, settings: settings) == "Cursor")
        #expect(AppMatcher.matches(safari, settings: settings) == nil)

        #expect(KeyClassifier.classify(keyCode: 8, modifiers: [.command]) == .ignored) // Cmd+C
        #expect(KeyClassifier.classify(keyCode: 55, modifiers: [.command]) == .ignored) // Cmd modifier key
        #expect(KeyClassifier.classify(keyCode: 53, modifiers: []) == .ignored) // Escape
        #expect(KeyClassifier.classify(keyCode: 123, modifiers: []) == .ignored) // Left arrow
        #expect(KeyClassifier.classify(keyCode: 9, modifiers: [.command]) == .typing) // Cmd+V paste
        #expect(KeyClassifier.classify(keyCode: 0, modifiers: []) == .typing) // 'A'

        var machine = SuppressionStateMachine(settings: settings)
        #expect(machine.handleKeyAction(.typing, matchedAppName: nil, now: baseDate) == .none)
        #expect(machine.handleKeyAction(.promptSent, matchedAppName: "Claude", now: baseDate) == .none)
        #expect(machine.state == .idle)
    }

    @Test("Custom pause durations and disabling master switch work as expected")
    func customDurationsAndDisable() throws {
        var customSettings = PromptQuietSettings(
            isEnabled: true,
            typingPauseSeconds: 35,
            postSendPauseSeconds: 8
        )
        var machine = SuppressionStateMachine(settings: customSettings)

        #expect(machine.handleKeyAction(.typing, matchedAppName: "Antigravity", now: baseDate) == .suppress)
        #expect(machine.remainingSeconds(at: baseDate) == 35)

        #expect(machine.handleKeyAction(.promptSent, matchedAppName: "Antigravity", now: baseDate.addingTimeInterval(5)) == .none)
        #expect(machine.remainingSeconds(at: baseDate.addingTimeInterval(5)) == 8)

        customSettings.isEnabled = false
        #expect(machine.updateSettings(customSettings, now: baseDate.addingTimeInterval(6)) == .resume)
        #expect(machine.state == .idle)

        let data = try customSettings.encodeJSON()
        let decoded = try PromptQuietSettings.decodeJSON(from: data)
        #expect(decoded == customSettings)
    }

    @Test("Post-send delay of None (0s) resumes notifications immediately when sending prompt")
    func postSendNoneResumesImmediately() {
        let settings = PromptQuietSettings(typingPauseSeconds: 15, postSendPauseSeconds: 0)
        var machine = SuppressionStateMachine(settings: settings)

        #expect(machine.handleKeyAction(.typing, matchedAppName: "Claude", now: baseDate) == .suppress)
        #expect(machine.isSuppressing)

        let sendEffect = machine.handleKeyAction(.promptSent, matchedAppName: "Claude", now: baseDate.addingTimeInterval(2))
        #expect(sendEffect == .resume)
        #expect(!machine.isSuppressing)
        #expect(machine.state == .idle)
    }

    @Test("Timer settings clamp to 3-60s typing and 0-60s post-send")
    func pauseRangesClamped() {
        let low = PromptQuietSettings(typingPauseSeconds: 1, postSendPauseSeconds: -5)
        #expect(low.typingPauseSeconds == 3)
        #expect(low.postSendPauseSeconds == 0)

        let high = PromptQuietSettings(typingPauseSeconds: 120, postSendPauseSeconds: 90)
        #expect(high.typingPauseSeconds == 60)
        #expect(high.postSendPauseSeconds == 60)
    }

    @Test("Insane Focus Mode pauses notifications indefinitely until turned off")
    func insaneFocusModeIndefinite() {
        var settings = PromptQuietSettings()
        var machine = SuppressionStateMachine(settings: settings)

        #expect(machine.setManualPause(true) == .suppress)
        #expect(machine.state == .manuallyPaused)
        #expect(machine.remainingSeconds(at: baseDate) == nil)

        #expect(machine.tick(now: baseDate.addingTimeInterval(10_000)) == .none)
        #expect(machine.handleKeyAction(.typing, matchedAppName: "Cursor", now: baseDate) == .none)
        #expect(machine.handleKeyAction(.promptSent, matchedAppName: "Cursor", now: baseDate) == .none)

        settings.isEnabled = false
        #expect(machine.updateSettings(settings, now: baseDate) == .none)
        #expect(machine.state == .manuallyPaused)

        #expect(machine.setManualPause(false) == .resume)
        #expect(machine.state == .idle)
    }
}
