import Foundation

/// Modifier flags observed on a keyboard event without inspecting typed characters.
public struct KeyModifiers: OptionSet, Sendable, Equatable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let command = KeyModifiers(rawValue: 1 << 1)
    public static let control = KeyModifiers(rawValue: 1 << 2)
    public static let option = KeyModifiers(rawValue: 1 << 3)
}

/// High-level semantic classification of a keystroke for notification suppression timers.
public enum KeyAction: Sendable, Equatable {
    case typing
    case promptSent
    case ignored
}

/// Privacy-safe keystroke classifier that inspects only macOS virtual key codes and modifier flags.
public enum KeyClassifier: Sendable {
    private static let modifierKeyCodes: Set<UInt16> = [
        54, 55, // Right/Left Command
        56, 60, // Left/Right Shift
        57,     // Caps Lock
        58, 61, // Left/Right Option
        59, 62, // Left/Right Control
        63      // Fn
    ]

    private static let escapeAndFunctionKeyCodes: Set<UInt16> = [
        53, // Escape
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, // F1-F12
        105, 107, 113, 106, 64, 79, 80, 90 // F13-F20
    ]

    private static let navigationKeyCodes: Set<UInt16> = [
        123, 124, 125, 126, // Arrows
        115, 119, 116, 121  // Home, End, PageUp, PageDown
    ]

    private static let returnKeyCodes: Set<UInt16> = [
        36, // Return
        76  // Keypad Enter
    ]

    private static let editShortcutKeyCodes: Set<UInt16> = [
        6,   // Z (Undo)
        7,   // X (Cut)
        9,   // V (Paste)
        51,  // Backspace / Delete
        117  // Forward Delete
    ]

    public static func classify(
        keyCode: UInt16,
        modifiers: KeyModifiers,
        isAutoRepeat: Bool = false
    ) -> KeyAction {
        _ = isAutoRepeat

        if modifierKeyCodes.contains(keyCode) ||
            escapeAndFunctionKeyCodes.contains(keyCode) ||
            navigationKeyCodes.contains(keyCode) {
            return .ignored
        }

        if returnKeyCodes.contains(keyCode) {
            if modifiers.contains(.shift) {
                return .typing
            }
            if (modifiers.contains(.option) || modifiers.contains(.control)) && !modifiers.contains(.command) {
                return .typing
            }
            return .promptSent
        }

        if modifiers.contains(.command) || modifiers.contains(.control) {
            if modifiers.contains(.command),
               !modifiers.contains(.control),
               editShortcutKeyCodes.contains(keyCode) {
                return .typing
            }
            return .ignored
        }

        return .typing
    }
}
