# PromptQuiet

A lightweight macOS top-menu-bar utility (`LSUIElement` / `.accessory`) that silently pauses macOS notifications while you type into **Claude**, **ChatGPT**, **Antigravity**, or **Cursor**, without triggering Focus Mode ("Do Not Disturb On/Off") banners.

## Features & Behavior

- **Target Apps**: Built-in switches for **Claude**, **ChatGPT**, **Antigravity**, and **Cursor**, plus custom bundle IDs via **+ Add App…** (with one-click quick-add for the last active app).
- **Typing Pause (`3s`–`60s`, default `20s`)**: Typing inside any enabled app suppresses notifications and resets the countdown. Pressing `Shift+Return` adds a newline and keeps the typing timer active.
- **After Prompt Sent (`None`–`60s`, default `5s`)**: Pressing `Return` or `Cmd+Return` switches to the post-send wait before turning notifications back on. Setting this slider to **None** (`0s`) restores notifications immediately upon sending. Typing again during the countdown cancels it and restores the typing timer.
- **Insane Focus Mode**: Optional checkbox that pauses all notifications indefinitely across every app until unchecked (independent of **Auto-Silence Typing**).
- **Stop Dock Bouncing**: Optional toggle that suppresses vertical Dock icon attention-bouncing (`com.apple.dock` `no-bouncing`, backed by `~/Library/Application Support/PromptQuiet/dock_nobounce.lock` crash recovery) only while notifications are paused, and restores normal Dock bouncing as soon as notifications resume—without freezing the Dock, so Spaces, Mission Control, and `Cmd+Tab` continue working normally.
- **Menu Bar UI & Hover Explanations**: Native AppKit `NSStatusItem` + borderless frosted `NSPanel` with all preferences expanded inline, hover `(i)` tooltips across controls and modes, optional fixed-width **Menu Bar Countdown**, **Launch at Login**, and **Reset Daemon** safety recovery.
- **Zero-Keylogging Privacy**: Uses a non-modifying `CGEventTap` (with an `NSEvent` global `keyDown` fallback) that inspects only virtual key codes and modifier flags (`Shift`, `Cmd`, `Ctrl`, `Opt`). Typed characters are never read or stored.

## Suppression Modes (Selectable in Menu Bar)

1. **Silent (`SIGSTOP` / `SIGCONT`) — Default**
   - Pauses `NotificationCenter` (`com.apple.notificationcenterui`) while `usernoted` queues incoming alerts in the background.
   - Produces zero Focus Mode banners and zero menu bar indicators.
   - Includes crash-recovery lockfile (`~/Library/Application Support/PromptQuiet/sigstop.lock`), `willTerminate`, `willSleepNotification`, `SIGINT`/`SIGTERM` handlers, and a manual **Reset Daemon** recovery action.
2. **Stream (`ScreenCaptureKit` 2×2 @ 1 fps)**
   - Runs a minimal `SCStream` capture session so macOS suppresses notification banners as if sharing the display.
   - Displays macOS's small purple menu bar indicator while active and requires **System Settings → Notifications → Allow notifications when mirroring or sharing the display** to be turned **OFF**.

## Architecture

- `Sources/PromptQuietCore`: Cross-platform Swift 6 library containing target-app matching (`AppMatcher`), keystroke classification (`KeyClassifier`), settings persistence (`PromptQuietSettings`), and the deterministic `SuppressionStateMachine`.
- `Tests/PromptQuietCoreTests`: 10 Swift `Testing` unit tests covering timers, `None` (`0s`) post-send, Insane Focus Mode, key classification, app matching, and legacy settings upgrades.
- `Sources/PromptQuietApp`: Native macOS menu bar application (`AppDelegate` / `StatusBarController`, `InputMonitor`, `AppController`, `MenuBarView`, `NotificationCenterPauseBackend`, `ScreenCaptureStreamBackend`, `DockBounceController`).
- `Dockerfile` & `docker-compose.yml`: Builds and runs `PromptQuietCore` tests in a Linux `swift:6.0` container (macOS UI and notification APIs require macOS).
- `scripts/bundle-app.sh` & `Makefile`: Builds, ad-hoc signs, registers in LaunchServices, and packages `dist/PromptQuiet.app`.

## Quickstart

```bash
# Build and launch the macOS menu bar app
make run

# Or build dist/PromptQuiet.app only
make app

# Run macOS host tests (uses Xcode toolchain for SwiftUI/Testing macros)
make test

# Run PromptQuietCore tests in Docker (Linux Swift 6)
make docker-test
```

## Permissions Note

On first launch, click **Grant Accessibility Access** in the PromptQuiet menu bar popover and enable **PromptQuiet.app** in **System Settings → Privacy & Security → Device Control / Accessibility**. Because `dist/PromptQuiet.app` is ad-hoc signed during local builds, `scripts/bundle-app.sh` registers the bundle with LaunchServices and resets stale TCC entries (`tccutil reset All com.promptquiet.app`) whenever the compiled binary changes; if an older build remains listed in System Settings, use the **Reset** button next to **Grant Accessibility Access**.

## License

Licensed under the [GNU General Public License v3.0](LICENSE).
