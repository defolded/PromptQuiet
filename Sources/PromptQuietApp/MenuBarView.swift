import PromptQuietCore
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var controller: AppController
    @State private var customBundleInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader

            if !controller.isAccessibilityTrusted {
                accessibilityBanner
            }

            if let error = controller.backendError {
                errorBanner(error)
            }

            Divider()

            timersSection

            Divider()

            targetAppsSection

            Divider()

            suppressionModeSection

            Divider()

            footerSection
        }
        .padding(14)
        .frame(width: 348)
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: controller.menuBarSymbolName)
                    .font(.title3)
                    .foregroundStyle(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("PromptQuiet")
                        .font(.headline)
                    Text(controller.statusHeadline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                Toggle(
                    "",
                    isOn: Binding(
                        get: { controller.settings.isEnabled },
                        set: { controller.setEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }

            HStack(spacing: 8) {
                if controller.isSuppressing {
                    Button {
                        controller.resumeNow()
                    } label: {
                        Label("Resume Notifications Now", systemImage: "bell.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button {
                    controller.toggleManualPause()
                } label: {
                    Label(
                        controller.isManuallyPaused ? "End Manual Pause" : "Pause Manually",
                        systemImage: controller.isManuallyPaused ? "play.fill" : "pause.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var accessibilityBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Accessibility Permission Needed", systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("PromptQuiet monitors key codes (never characters) to detect typing in Claude, Antigravity, and Cursor.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Grant Accessibility Access") {
                controller.grantAccessibilityPermission()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Suppression Error", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var timersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pause Timers")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            // Stop-typing pause (default 20s)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("After stopping typing")
                        .font(.subheadline)
                    Spacer()
                    Stepper(
                        "\(controller.settings.typingPauseSeconds)s",
                        value: Binding(
                            get: { controller.settings.typingPauseSeconds },
                            set: { controller.setTypingPauseSeconds($0) }
                        ),
                        in: PromptQuietSettings.typingPauseRange
                    )
                    .font(.subheadline.monospacedDigit())
                }

                Slider(
                    value: Binding(
                        get: { Double(min(controller.settings.typingPauseSeconds, 120)) },
                        set: { controller.setTypingPauseSeconds(Int($0.rounded())) }
                    ),
                    in: 5...120,
                    step: 1
                )

                HStack(spacing: 6) {
                    ForEach([10, 20, 30, 60], id: \.self) { preset in
                        presetButton(
                            seconds: preset,
                            selected: controller.settings.typingPauseSeconds == preset
                        ) {
                            controller.setTypingPauseSeconds(preset)
                        }
                    }
                }
            }

            // Post-send pause (default 5s)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("After sending prompt")
                        .font(.subheadline)
                    Spacer()
                    Stepper(
                        "\(controller.settings.postSendPauseSeconds)s",
                        value: Binding(
                            get: { controller.settings.postSendPauseSeconds },
                            set: { controller.setPostSendPauseSeconds($0) }
                        ),
                        in: PromptQuietSettings.postSendPauseRange
                    )
                    .font(.subheadline.monospacedDigit())
                }

                Slider(
                    value: Binding(
                        get: { Double(min(controller.settings.postSendPauseSeconds, 30)) },
                        set: { controller.setPostSendPauseSeconds(Int($0.rounded())) }
                    ),
                    in: 1...30,
                    step: 1
                )

                HStack(spacing: 6) {
                    ForEach([3, 5, 10], id: \.self) { preset in
                        presetButton(
                            seconds: preset,
                            selected: controller.settings.postSendPauseSeconds == preset
                        ) {
                            controller.setPostSendPauseSeconds(preset)
                        }
                    }
                    Spacer()
                    Text("Shift+Return keeps 20s")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var targetAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Target Apps")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(BuiltInApp.allCases) { app in
                    Toggle(
                        app.displayName,
                        isOn: Binding(
                            get: { controller.settings.enabledApps.contains(app) },
                            set: { controller.toggleBuiltInApp(app, enabled: $0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .font(.subheadline)
                }
            }

            if !controller.settings.customBundleIdentifiers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(controller.settings.customBundleIdentifiers, id: \.self) { bundleID in
                        HStack {
                            Text(bundleID)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                controller.removeCustomBundleIdentifier(bundleID)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("Add custom bundle ID...", text: $customBundleInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit(submitCustomBundleID)

                Button("Add") {
                    submitCustomBundleID()
                }
                .controlSize(.small)
                .disabled(customBundleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let recentApp = controller.lastObservedExternalApp,
               let recentBundle = recentApp.bundleIdentifier,
               AppMatcher.matches(recentApp, settings: controller.settings) == nil {
                Button {
                    controller.addCustomBundleIdentifier(recentBundle)
                } label: {
                    Label(
                        "Add Last App (\(recentApp.localizedName ?? recentBundle))",
                        systemImage: "plus.app"
                    )
                    .font(.caption2)
                }
                .buttonStyle(.link)
            }
        }
    }

    private var suppressionModeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Suppression Engine")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker(
                "Engine",
                selection: Binding(
                    get: { controller.settings.suppressionMode },
                    set: { controller.setSuppressionMode($0) }
                )
            ) {
                ForEach(SuppressionMode.allCases) { mode in
                    Text(mode.shortLabel).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(engineDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(
                "Show countdown in menu bar",
                isOn: Binding(
                    get: { controller.settings.showCountdownInMenuBar },
                    set: { controller.setShowCountdownInMenuBar($0) }
                )
            )
            .font(.caption)

            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { controller.launchAtLogin },
                    set: { controller.setLaunchAtLogin($0) }
                )
            )
            .font(.caption)

            HStack {
                Button("Force Resume NotificationCenter") {
                    controller.forceResumeNotificationCenter()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Quit") {
                    controller.quitApp()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
    }

    private var statusColor: Color {
        if !controller.isAccessibilityTrusted {
            return .orange
        }
        if !controller.settings.isEnabled {
            return .secondary
        }
        switch controller.state {
        case .idle:
            return .primary
        case .typingPaused, .postSendPaused:
            return .indigo
        case .manuallyPaused:
            return .purple
        }
    }

    private var engineDescription: String {
        switch controller.settings.suppressionMode {
        case .notificationCenterPause:
            return "Zero banners and zero menu bar indicators. Pauses NotificationCenter via SIGSTOP and automatically restores it on idle, sleep, or quit."
        case .screenCaptureStream:
            return "Official 2x2 @ 1fps ScreenCaptureKit stream. Shows a small purple menu bar icon while active; requires 'Allow notifications when mirroring or sharing' OFF in System Settings."
        }
    }

    private func presetButton(seconds: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button("\(seconds)s", action: action)
            .font(.caption2.monospacedDigit())
            .buttonStyle(.bordered)
            .tint(selected ? .accentColor : .secondary)
            .controlSize(.mini)
    }

    private func submitCustomBundleID() {
        controller.addCustomBundleIdentifier(customBundleInput)
        customBundleInput = ""
    }
}
