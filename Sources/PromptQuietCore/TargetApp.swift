import Foundation

/// Matches the frontmost application against enabled built-in and custom target apps.
public struct AppMatcher: Sendable {
    /// Returns the display name of the matched target application, or `nil` if the app is not targeted.
    public static func matches(_ app: RunningAppInfo, settings: PromptQuietSettings) -> String? {
        let normalizedBundleID = app.bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedName = app.localizedName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        for builtIn in BuiltInApp.allCases where settings.enabledApps.contains(builtIn) {
            if let bundleID = normalizedBundleID,
               builtIn.bundleIdentifiers.contains(where: { $0.lowercased() == bundleID }) {
                return builtIn.displayName
            }

            if let name = normalizedName,
               builtIn.nameKeywords.contains(where: { $0.lowercased() == name }) {
                return builtIn.displayName
            }
        }

        if let bundleID = normalizedBundleID, !bundleID.isEmpty {
            for custom in settings.customBundleIdentifiers {
                let candidate = custom.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !candidate.isEmpty && candidate == bundleID {
                    if let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !name.isEmpty {
                        return name
                    }
                    return custom.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        return nil
    }
}
