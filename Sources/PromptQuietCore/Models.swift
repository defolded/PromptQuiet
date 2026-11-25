import Foundation

/// Notification suppression mechanism used while typing or immediately after sending a prompt.
public enum SuppressionMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case notificationCenterPause
    case screenCaptureStream

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .notificationCenterPause:
            return "Silent Daemon Pause (SIGSTOP)"
        case .screenCaptureStream:
            return "ScreenCaptureKit Stream (SCStream)"
        }
    }

    public var shortLabel: String {
        switch self {
        case .notificationCenterPause:
            return "Silent Daemon Pause"
        case .screenCaptureStream:
            return "ScreenCaptureKit Stream"
        }
    }
}

/// Supported built-in target applications where prompt typing triggers notification suppression.
public enum BuiltInApp: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case claude
    case chatgpt
    case antigravity
    case cursor

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude:
            return "Claude"
        case .chatgpt:
            return "ChatGPT"
        case .antigravity:
            return "Antigravity"
        case .cursor:
            return "Cursor"
        }
    }

    public var bundleIdentifiers: [String] {
        switch self {
        case .claude:
            return ["com.anthropic.claudefordesktop"]
        case .chatgpt:
            return ["com.openai.chat", "com.openai.codex", "com.openai.chatgpt"]
        case .antigravity:
            return ["com.google.antigravity"]
        case .cursor:
            return ["com.todesktop.230313mzl4w4u92", "com.cursor.Cursor"]
        }
    }

    public var nameKeywords: [String] {
        switch self {
        case .claude:
            return ["claude"]
        case .chatgpt:
            return ["chatgpt"]
        case .antigravity:
            return ["antigravity"]
        case .cursor:
            return ["cursor"]
        }
    }
}

/// Preset durations for timed Insane Focus Mode.
public enum InsaneFocusDuration: Int, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case fortyFiveMinutes = 45
    case oneHour = 60

    public var id: Int { rawValue }

    public var seconds: Int { rawValue * 60 }

    public var timeInterval: TimeInterval { TimeInterval(seconds) }

    public var shortLabel: String {
        switch self {
        case .fiveMinutes:
            return "5m"
        case .fifteenMinutes:
            return "15m"
        case .thirtyMinutes:
            return "30m"
        case .fortyFiveMinutes:
            return "45m"
        case .oneHour:
            return "1hr"
        }
    }

    public var descriptionLabel: String {
        switch self {
        case .fiveMinutes:
            return "5 minutes"
        case .fifteenMinutes:
            return "15 minutes"
        case .thirtyMinutes:
            return "30 minutes"
        case .fortyFiveMinutes:
            return "45 minutes"
        case .oneHour:
            return "1 hour"
        }
    }
}

/// Lightweight cross-platform representation of the currently active application.
public struct RunningAppInfo: Sendable, Equatable {
    public let bundleIdentifier: String?
    public let localizedName: String?

    public init(bundleIdentifier: String?, localizedName: String?) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
    }
}
