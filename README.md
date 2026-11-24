# PromptQuiet

A lightweight macOS top-menu-bar utility (`LSUIElement = true`) that silently pauses macOS notifications while you type into **Claude**, **ChatGPT**, **Antigravity**, or **Cursor**, without triggering Focus Mode ("Do Not Disturb On/Off") banners.

## Behavior

- **Stop-Typing Delay (default `20s`)**: Any typing inside Claude, ChatGPT, Antigravity, or Cursor suppresses notifications and resets the countdown. Once you stop typing, notifications resume after `20s` (adjustable from the menu bar).
- **After Sending Prompt (default `5s`)**: Pressing `Return` or `Cmd+Return` switches to a `5s` post-send countdown (also adjustable from the menu bar). Pressing `Shift+Return` adds a newline and keeps the `20s` typing timer. Typing again during the `5s` countdown cancels it and restores the `20s` typing timer.
- **Zero-Keylogging Privacy**: Uses a `.listenOnly` `CGEventTap` that inspects only virtual key codes and modifier flags (`Shift`, `Cmd`, `Ctrl`, `Opt`). Typed characters are never read or stored.

## Suppression Engines (Selectable in Menu Bar)

1. **Silent Daemon Pause (`SIGSTOP` / `SIGCONT`) — Default**
   - Pauses `NotificationCenter` (`com.apple.notificationcenterui`) while `usernoted` continues queuing alerts in the background.
   - Zero Focus Mode popups and zero menu bar indicators.
   - Includes crash-recovery lockfile (`~/Library/Application Support/PromptQuiet/sigstop.lock`), `willTerminate`, `willSleepNotification`, `SIGINT`/`SIGTERM` handlers, and a manual **Force Resume NotificationCenter** safety button.
2. **ScreenCaptureKit Stream (`SCStream` 2x2 @ 1 fps) — Selectable**
   - Uses Apple's official `ScreenCaptureKit` framework to trigger macOS screen-sharing banner suppression.
   - Displays macOS's small purple menu-bar indicator while active and requires **System Settings → Notifications → Allow notifications when mirroring or sharing the display** to be turned **OFF**.

## Architecture

- `Sources/PromptQuietCore`: Cross-platform Swift 6 library containing target-app matching, keystroke classification, settings, and the deterministic `SuppressionStateMachine`.
- `Tests/PromptQuietCoreTests`: Unit tests written with Swift `Testing`.
- `Sources/PromptQuietApp`: Native macOS Menu Bar app (`SwiftUI`, `AppKit`, `CGEventTap`, `ScreenCaptureKit`).
- `Dockerfile` & `docker-compose.yml`: Runs `PromptQuietCore` release build and tests in a Linux `swift:6.0` container (macOS UI/Notification APIs require macOS).

## Quickstart

```bash
# Build and launch the macOS menu bar app
make run

# Or build dist/PromptQuiet.app only
make app

# Run macOS host tests (requires Xcode toolchain for SwiftUI/Testing macros)
make test

# Run PromptQuietCore tests in Docker (Linux Swift 6)
make docker-test
```

On first launch, click **Grant Accessibility Access** in the PromptQuiet menu bar popover so macOS allows the `.listenOnly` key-code monitor.

## License

Licensed under the [GNU General Public License v3.0](LICENSE).
