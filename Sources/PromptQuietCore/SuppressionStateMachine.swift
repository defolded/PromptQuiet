import Foundation

/// Current notification suppression state managed by `SuppressionStateMachine`.
public enum SuppressionState: Equatable, Sendable {
    case idle
    case typingPaused(expiresAt: Date, appName: String)
    case postSendPaused(expiresAt: Date, appName: String)
    case manuallyPaused(expiresAt: Date?)

    public var isManuallyPaused: Bool {
        if case .manuallyPaused = self {
            return true
        }
        return false
    }
}

/// Side effect requested by `SuppressionStateMachine` after a state transition.
public enum SuppressionEffect: Equatable, Sendable {
    case none
    case suppress
    case resume
}

/// Deterministic state machine controlling stop-typing, post-send, and Insane Focus notification pauses.
public struct SuppressionStateMachine: Sendable {
    public private(set) var state: SuppressionState = .idle
    public private(set) var settings: PromptQuietSettings

    public init(settings: PromptQuietSettings = PromptQuietSettings()) {
        var normalized = settings
        normalized.normalize()
        self.settings = normalized
    }

    public var isSuppressing: Bool {
        state != .idle
    }

    public var isManuallyPaused: Bool {
        state.isManuallyPaused
    }

    public func remainingSeconds(at now: Date) -> Int? {
        switch state {
        case .typingPaused(let expiresAt, _),
             .postSendPaused(let expiresAt, _),
             .manuallyPaused(let expiresAt?):
            let remaining = expiresAt.timeIntervalSince(now)
            return max(0, Int(ceil(remaining)))
        case .idle, .manuallyPaused(nil):
            return nil
        }
    }

    public mutating func handleKeyAction(
        _ action: KeyAction,
        matchedAppName: String?,
        now: Date
    ) -> SuppressionEffect {
        guard settings.isEnabled,
              !state.isManuallyPaused,
              let appName = matchedAppName else {
            return .none
        }

        switch action {
        case .ignored:
            return .none

        case .typing:
            let wasIdle = (state == .idle)
            let expiresAt = now.addingTimeInterval(TimeInterval(settings.typingPauseSeconds))
            state = .typingPaused(expiresAt: expiresAt, appName: appName)
            return wasIdle ? .suppress : .none

        case .promptSent:
            switch state {
            case .typingPaused, .postSendPaused:
                if settings.postSendPauseSeconds <= 0 {
                    state = .idle
                    return .resume
                }
                let expiresAt = now.addingTimeInterval(TimeInterval(settings.postSendPauseSeconds))
                state = .postSendPaused(expiresAt: expiresAt, appName: appName)
                return .none
            case .idle, .manuallyPaused:
                return .none
            }
        }
    }

    public mutating func tick(now: Date) -> SuppressionEffect {
        switch state {
        case .typingPaused(let expiresAt, _),
             .postSendPaused(let expiresAt, _),
             .manuallyPaused(let expiresAt?):
            if now >= expiresAt {
                state = .idle
                return .resume
            }
            return .none
        case .idle, .manuallyPaused(nil):
            return .none
        }
    }

    public mutating func resumeNow() -> SuppressionEffect {
        guard state != .idle else { return .none }
        state = .idle
        return .resume
    }

    public mutating func setManualPause(
        _ paused: Bool,
        durationSeconds: TimeInterval? = nil,
        now: Date = Date()
    ) -> SuppressionEffect {
        if paused {
            let wasIdle = (state == .idle)
            let expiresAt = durationSeconds.map { now.addingTimeInterval(max(1, $0)) }
            state = .manuallyPaused(expiresAt: expiresAt)
            return wasIdle ? .suppress : .none
        } else {
            guard state.isManuallyPaused else { return .none }
            state = .idle
            return .resume
        }
    }

    public mutating func updateSettings(_ newSettings: PromptQuietSettings, now: Date) -> SuppressionEffect {
        var normalized = newSettings
        normalized.normalize()
        settings = normalized

        if !settings.isEnabled && state != .idle && !state.isManuallyPaused {
            state = .idle
            return .resume
        }

        switch state {
        case .typingPaused(let expiresAt, let appName):
            let maxExpiresAt = now.addingTimeInterval(TimeInterval(settings.typingPauseSeconds))
            if expiresAt > maxExpiresAt {
                state = .typingPaused(expiresAt: maxExpiresAt, appName: appName)
            }
        case .postSendPaused(let expiresAt, let appName):
            if settings.postSendPauseSeconds <= 0 {
                state = .idle
                return .resume
            }
            let maxExpiresAt = now.addingTimeInterval(TimeInterval(settings.postSendPauseSeconds))
            if expiresAt > maxExpiresAt {
                state = .postSendPaused(expiresAt: maxExpiresAt, appName: appName)
            }
        case .idle, .manuallyPaused:
            break
        }

        return .none
    }
}
