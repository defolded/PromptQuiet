import Foundation

/// Persistent user configuration for PromptQuiet.
public struct PromptQuietSettings: Codable, Equatable, Sendable {
    public static let typingPauseRange = 3...60
    public static let postSendPauseRange = 0...60

    public var isEnabled: Bool
    public var typingPauseSeconds: Int
    public var postSendPauseSeconds: Int
    public var suppressionMode: SuppressionMode
    public var enabledApps: Set<BuiltInApp>
    public var knownApps: Set<BuiltInApp>?
    public var customBundleIdentifiers: [String]
    public var showCountdownInMenuBar: Bool
    public var suppressDockBouncing: Bool

    public init(
        isEnabled: Bool = true,
        typingPauseSeconds: Int = 20,
        postSendPauseSeconds: Int = 5,
        suppressionMode: SuppressionMode = .notificationCenterPause,
        enabledApps: Set<BuiltInApp> = Set(BuiltInApp.allCases),
        knownApps: Set<BuiltInApp>? = Set(BuiltInApp.allCases),
        customBundleIdentifiers: [String] = [],
        showCountdownInMenuBar: Bool = true,
        suppressDockBouncing: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.typingPauseSeconds = Self.clampTypingPause(typingPauseSeconds)
        self.postSendPauseSeconds = Self.clampPostSendPause(postSendPauseSeconds)
        self.suppressionMode = suppressionMode
        self.enabledApps = enabledApps
        self.knownApps = knownApps
        self.customBundleIdentifiers = customBundleIdentifiers
        self.showCountdownInMenuBar = showCountdownInMenuBar
        self.suppressDockBouncing = suppressDockBouncing
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case typingPauseSeconds
        case postSendPauseSeconds
        case suppressionMode
        case enabledApps
        case knownApps
        case customBundleIdentifiers
        case showCountdownInMenuBar
        case suppressDockBouncing
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.typingPauseSeconds = try container.decodeIfPresent(Int.self, forKey: .typingPauseSeconds) ?? 20
        self.postSendPauseSeconds = try container.decodeIfPresent(Int.self, forKey: .postSendPauseSeconds) ?? 5
        self.suppressionMode = try container.decodeIfPresent(SuppressionMode.self, forKey: .suppressionMode) ?? .notificationCenterPause
        self.enabledApps = try container.decodeIfPresent(Set<BuiltInApp>.self, forKey: .enabledApps) ?? Set(BuiltInApp.allCases)
        self.knownApps = try container.decodeIfPresent(Set<BuiltInApp>.self, forKey: .knownApps)
        self.customBundleIdentifiers = try container.decodeIfPresent([String].self, forKey: .customBundleIdentifiers) ?? []
        self.showCountdownInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showCountdownInMenuBar) ?? true
        self.suppressDockBouncing = try container.decodeIfPresent(Bool.self, forKey: .suppressDockBouncing) ?? false
    }

    public static func clampTypingPause(_ value: Int) -> Int {
        min(max(value, typingPauseRange.lowerBound), typingPauseRange.upperBound)
    }

    public static func clampPostSendPause(_ value: Int) -> Int {
        min(max(value, postSendPauseRange.lowerBound), postSendPauseRange.upperBound)
    }

    public mutating func normalize() {
        typingPauseSeconds = Self.clampTypingPause(typingPauseSeconds)
        postSendPauseSeconds = Self.clampPostSendPause(postSendPauseSeconds)
        let allApps = Set(BuiltInApp.allCases)
        if let known = knownApps {
            enabledApps.formUnion(allApps.subtracting(known))
        } else {
            enabledApps.insert(.chatgpt)
        }
        knownApps = allApps
        customBundleIdentifiers = customBundleIdentifiers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public func encodeJSON() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decodeJSON(from data: Data) throws -> PromptQuietSettings {
        var decoded = try JSONDecoder().decode(PromptQuietSettings.self, from: data)
        decoded.normalize()
        return decoded
    }
}

/// Storage abstraction for loading and saving `PromptQuietSettings`.
public protocol SettingsStore: Sendable {
    func load() -> PromptQuietSettings
    func save(_ settings: PromptQuietSettings)
}

/// Thread-safe in-memory settings store suitable for tests and non-Apple environments.
public final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: PromptQuietSettings

    public init(initialSettings: PromptQuietSettings = PromptQuietSettings()) {
        var normalized = initialSettings
        normalized.normalize()
        self.storage = normalized
    }

    public func load() -> PromptQuietSettings {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public func save(_ settings: PromptQuietSettings) {
        var normalized = settings
        normalized.normalize()
        lock.lock()
        storage = normalized
        lock.unlock()
    }
}
