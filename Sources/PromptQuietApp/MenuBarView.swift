import PromptQuietCore
import SwiftUI

private let accentGreen = Color(red: 0.16, green: 0.80, blue: 0.25)

private struct TooltipPayload: @unchecked Sendable {
    let text: String
    let anchor: Anchor<CGRect>
}

private struct TooltipAnchorKey: PreferenceKey {
    static let defaultValue: TooltipPayload? = nil

    static func reduce(value: inout TooltipPayload?, nextValue: () -> TooltipPayload?) {
        value = value ?? nextValue()
    }
}

private struct HoverTooltipModifier: ViewModifier {
    let text: String
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering = $0 }
            .anchorPreference(key: TooltipAnchorKey.self, value: .bounds) { anchor in
                isHovering ? TooltipPayload(text: text, anchor: anchor) : nil
            }
    }
}

private extension View {
    func hoverTooltip(_ text: String) -> some View {
        modifier(HoverTooltipModifier(text: text))
    }
}

private struct InfoHintIcon: View {
    let text: String
    @State private var isHovering = false

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 11.5))
            .foregroundStyle(isHovering ? Color.primary : Color.secondary.opacity(0.75))
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .anchorPreference(key: TooltipAnchorKey.self, value: .bounds) { anchor in
                isHovering ? TooltipPayload(text: text, anchor: anchor) : nil
            }
    }
}

private struct PopoverBubbleShape: Shape {
    let arrowX: CGFloat
    var arrowWidth: CGFloat = 26
    var arrowHeight: CGFloat = 11
    var cornerRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        let minX = rect.minX
        let maxX = rect.maxX
        let bodyTop = rect.minY + arrowHeight
        let maxY = rect.maxY
        let r = min(cornerRadius, min(rect.width / 2, (maxY - bodyTop) / 2))

        let clampedArrowX = min(max(arrowX, minX + r + arrowWidth / 2 + 4), maxX - r - arrowWidth / 2 - 4)
        let arrowStart = clampedArrowX - arrowWidth / 2
        let arrowEnd = clampedArrowX + arrowWidth / 2
        let tipY = rect.minY + 1
        let controlOffset: CGFloat = 6

        var path = Path()
        path.move(to: CGPoint(x: minX + r, y: bodyTop))

        path.addLine(to: CGPoint(x: arrowStart, y: bodyTop))
        path.addCurve(
            to: CGPoint(x: clampedArrowX, y: tipY),
            control1: CGPoint(x: arrowStart + controlOffset, y: bodyTop),
            control2: CGPoint(x: clampedArrowX - controlOffset * 0.65, y: tipY)
        )
        path.addCurve(
            to: CGPoint(x: arrowEnd, y: bodyTop),
            control1: CGPoint(x: clampedArrowX + controlOffset * 0.65, y: tipY),
            control2: CGPoint(x: arrowEnd - controlOffset, y: bodyTop)
        )

        path.addLine(to: CGPoint(x: maxX - r, y: bodyTop))
        path.addArc(
            center: CGPoint(x: maxX - r, y: bodyTop + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: maxX, y: maxY - r))
        path.addArc(
            center: CGPoint(x: maxX - r, y: maxY - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: minX + r, y: maxY))
        path.addArc(
            center: CGPoint(x: minX + r, y: maxY - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        path.addLine(to: CGPoint(x: minX, y: bodyTop + r))
        path.addArc(
            center: CGPoint(x: minX + r, y: bodyTop + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        path.closeSubpath()
        return path
    }
}

private struct MinimalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let accentColor: Color

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let span = max(range.upperBound - range.lowerBound, 1)
            let fraction = min(max((value - range.lowerBound) / span, 0), 1)
            let thumbDiameter: CGFloat = 15
            let usableWidth = max(width - thumbDiameter, 1)
            let thumbOffset = fraction * usableWidth
            let activeWidth = thumbOffset + thumbDiameter / 2

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 5)

                Capsule()
                    .fill(accentColor)
                    .frame(width: activeWidth, height: 5)

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                    )
                    .offset(x: thumbOffset)
            }
            .frame(height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let clampedX = min(max(gesture.location.x - thumbDiameter / 2, 0), usableWidth)
                        let newFraction = clampedX / usableWidth
                        value = (range.lowerBound + newFraction * span).rounded()
                    }
            )
        }
        .frame(height: 18)
    }
}

private struct SwitchRow: View {
    let title: String
    var hint: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.9))
            if let hint {
                InfoHintIcon(text: hint)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(accentGreen)
        }
    }
}

private struct HoverTextButton: View {
    let title: String
    var color: Color = .secondary
    var font: Font = .system(size: 13)
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .foregroundStyle(isHovering ? Color.primary : color)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct TimerSliderRow: View {
    let title: String
    let hint: String
    let value: Int
    let range: ClosedRange<Int>
    let zeroLabel: String?
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.9))
                InfoHintIcon(text: hint)

                Spacer()

                HStack(spacing: 6) {
                    HoverTextButton(title: "−", color: .secondary, font: .system(size: 14, weight: .medium)) {
                        onChange(max(range.lowerBound, value - 1))
                    }
                    .frame(width: 16)

                    Text(formattedValue)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 38, alignment: .center)

                    HoverTextButton(title: "+", color: .secondary, font: .system(size: 14, weight: .medium)) {
                        onChange(min(range.upperBound, value + 1))
                    }
                    .frame(width: 16)
                }
            }

            MinimalSlider(
                value: Binding(
                    get: { Double(min(max(value, range.lowerBound), range.upperBound)) },
                    set: { onChange(Int($0.rounded())) }
                ),
                range: Double(range.lowerBound)...Double(range.upperBound),
                accentColor: accentGreen
            )
        }
    }

    private var formattedValue: String {
        if value <= 0, let zeroLabel {
            return zeroLabel
        }
        return "\(value)s"
    }
}

private struct EnginePillPicker: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: SuppressionMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SuppressionMode.allCases) { mode in
                let isSelected = (selection == mode)
                Button {
                    selection = mode
                } label: {
                    Text(mode == .notificationCenterPause ? "Silent" : "Stream")
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(selectedFill(isSelected: isSelected))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            isSelected ? Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.08) : Color.clear,
                                            lineWidth: 0.5
                                        )
                                )
                                .shadow(
                                    color: isSelected ? .black.opacity(colorScheme == .dark ? 0.25 : 0.08) : .clear,
                                    radius: 1.5,
                                    y: 0.5
                                )
                        )
                }
                .buttonStyle(.plain)
                .hoverTooltip(tooltipText(for: mode))
            }
        }
        .padding(2)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color.black.opacity(0.32) : Color.primary.opacity(0.09))
        )
    }

    private func selectedFill(isSelected: Bool) -> Color {
        guard isSelected else { return Color.clear }
        return colorScheme == .dark ? Color.white.opacity(0.22) : Color.white.opacity(0.95)
    }

    private func tooltipText(for mode: SuppressionMode) -> String {
        switch mode {
        case .notificationCenterPause:
            return "Silent Daemon Pause (SIGSTOP): Freezes NotificationCenter while typing so zero banners and zero menu-bar icons appear. Queued alerts arrive when resumed. Auto-restores on idle, sleep, or quit."
        case .screenCaptureStream:
            return "ScreenCaptureKit Mode (SCStream): Starts an invisible 2×2 @ 1fps capture stream so macOS suppresses banners as if screen sharing. Shows a purple menu-bar indicator while active and requires 'Allow notifications when mirroring or sharing' OFF in System Settings → Notifications."
        }
    }
}

private struct InsaneFocusDurationRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let activePreset: InsaneFocusDuration?
    let onSelect: (InsaneFocusDuration) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(InsaneFocusDuration.allCases) { preset in
                let isSelected = (activePreset == preset)
                Button {
                    onSelect(preset)
                } label: {
                    Text(preset.shortLabel)
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? Color.purple : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(backgroundFill(isSelected: isSelected))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            isSelected ? Color.purple.opacity(0.45) : Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08),
                                            lineWidth: 0.75
                                        )
                                )
                        )
                }
                .buttonStyle(.plain)
                .hoverTooltip("Turn on Insane Focus Mode for \(preset.descriptionLabel). Notifications resume automatically when the timer ends.")
            }
        }
    }

    private func backgroundFill(isSelected: Bool) -> Color {
        if isSelected {
            return Color.purple.opacity(colorScheme == .dark ? 0.24 : 0.14)
        }
        return colorScheme == .dark ? Color.white.opacity(0.06) : Color.primary.opacity(0.05)
    }
}

struct MenuBarView: View {
    @ObservedObject var controller: AppController
    @State private var isAddingCustomApp = false
    @State private var customBundleInput = ""

    private let bubbleWidth: CGFloat = 328

    var body: some View {
        let bubbleShape = PopoverBubbleShape(arrowX: controller.popoverArrowX)

        VStack(spacing: 0) {
            headerSection
            hairlineDivider
            insaneFocusSection
            hairlineDivider
            appsSection
            hairlineDivider
            timersSection
            hairlineDivider
            preferencesSection
            hairlineDivider
            footerSection
        }
        .padding(.top, 11)
        .frame(width: bubbleWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(bubbleShape.fill(.thickMaterial))
        .clipShape(bubbleShape)
        .overlay(bubbleShape.stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .overlayPreferenceValue(TooltipAnchorKey.self) { payload in
            GeometryReader { proxy in
                if let payload {
                    tooltipCard(payload: payload, in: proxy)
                }
            }
        }
    }

    private var hairlineDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)

                Text("PromptQuiet")
                    .font(.system(size: 13.5, weight: .semibold))

                Spacer()

                Text(compactStatusText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(statusTextColor)
            }

            if !controller.isAccessibilityTrusted {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Button {
                            controller.grantAccessibilityPermission()
                        } label: {
                            Label("Grant Accessibility Access", systemImage: "hand.raised.fill")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity)
                                .background(Capsule().fill(.orange.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                        .hoverTooltip("Opens macOS Accessibility settings so PromptQuiet can detect keystrokes in Claude, ChatGPT, Antigravity, and Cursor. No typed text is ever read.")

                        Button {
                            controller.resetAndGrantAccessibilityPermission()
                        } label: {
                            Text("Reset")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.primary.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                        .hoverTooltip("Clears stale permission cache from older builds and re-prompts macOS.")

                        Button {
                            controller.refreshPermissions()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(6)
                                .background(Circle().fill(Color.primary.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                        .hoverTooltip("Re-check Accessibility permission status immediately.")
                    }

                    Text("Enable PromptQuiet in Device Control / Accessibility (click Reset if already listed from an older build).")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            if let error = controller.backendError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 11)
    }

    private var insaneFocusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Toggle(
                    isOn: Binding(
                        get: { controller.isManuallyPaused },
                        set: { controller.setInsaneFocus($0) }
                    )
                ) {
                    Text("Insane Focus Mode")
                        .font(.system(size: 13, weight: .medium))
                }
                .toggleStyle(.checkbox)
                .tint(accentGreen)

                InfoHintIcon(
                    text: "Check to pause all macOS notifications indefinitely until unchecked, or pick a quick duration below (5m–1hr) to resume automatically."
                )

                Spacer()

                if controller.isManuallyPaused {
                    Text(controller.formattedRemainingTime ?? "Indefinite")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.purple.opacity(0.14)))
                }
            }

            InsaneFocusDurationRow(activePreset: controller.activeInsaneFocusPreset) { preset in
                controller.startTimedInsaneFocus(preset)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text("Target Apps")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                InfoHintIcon(
                    text: "Typing inside any enabled app automatically silences notifications. Add custom bundle IDs for other tools."
                )
                Spacer()
            }

            ForEach(BuiltInApp.allCases) { app in
                SwitchRow(
                    title: app.displayName,
                    isOn: Binding(
                        get: { controller.settings.enabledApps.contains(app) },
                        set: { controller.toggleBuiltInApp(app, enabled: $0) }
                    )
                )
            }

            ForEach(controller.settings.customBundleIdentifiers, id: \.self) { bundleID in
                HStack {
                    Text(bundleID)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        controller.removeCustomBundleIdentifier(bundleID)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }

            if isAddingCustomApp {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        TextField("com.example.app", text: $customBundleInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .onSubmit(submitCustomBundleID)

                        HoverTextButton(title: "Add", color: accentGreen, font: .system(size: 12.5, weight: .semibold)) {
                            submitCustomBundleID()
                        }

                        HoverTextButton(title: "Cancel", color: .secondary, font: .system(size: 12)) {
                            customBundleInput = ""
                            isAddingCustomApp = false
                        }
                    }

                    if let recentApp = controller.lastObservedExternalApp,
                       let recentBundle = recentApp.bundleIdentifier,
                       AppMatcher.matches(recentApp, settings: controller.settings) == nil {
                        HoverTextButton(
                            title: "+ Use \(recentApp.localizedName ?? recentBundle)",
                            color: .secondary,
                            font: .system(size: 11.5)
                        ) {
                            controller.addCustomBundleIdentifier(recentBundle)
                            isAddingCustomApp = false
                        }
                    }
                }
                .padding(.top, 2)
            } else {
                HoverTextButton(
                    title: "+ Add App…",
                    color: .secondary,
                    font: .system(size: 12)
                ) {
                    isAddingCustomApp = true
                }
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
    }

    private var timersSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            TimerSliderRow(
                title: "Typing Pause",
                hint: "Seconds to wait after your last keystroke before turning notifications back on (3s to 60s). Pressing Shift+Return keeps this timer.",
                value: controller.settings.typingPauseSeconds,
                range: PromptQuietSettings.typingPauseRange,
                zeroLabel: nil
            ) { newValue in
                controller.setTypingPauseSeconds(newValue)
            }

            TimerSliderRow(
                title: "After Prompt Sent",
                hint: "Seconds to keep notifications off after pressing Return or Cmd+Return to send a prompt. Set to None (0s) to turn notifications back on immediately upon sending.",
                value: controller.settings.postSendPauseSeconds,
                range: PromptQuietSettings.postSendPauseRange,
                zeroLabel: "None"
            ) { newValue in
                controller.setPostSendPauseSeconds(newValue)
            }
        }
        .opacity(controller.isManuallyPaused ? 0.45 : 1.0)
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                Text("Mode")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.9))
                InfoHintIcon(
                    text: "Choose how PromptQuiet suppresses banners. Hover Silent or Stream to compare both engines."
                )
                Spacer()
                EnginePillPicker(
                    selection: Binding(
                        get: { controller.settings.suppressionMode },
                        set: { controller.setSuppressionMode($0) }
                    )
                )
            }

            SwitchRow(
                title: "Auto-Silence Typing",
                hint: "Enables automatic keystroke-triggered notification pausing in your selected target apps.",
                isOn: Binding(
                    get: { controller.settings.isEnabled },
                    set: { controller.setEnabled($0) }
                )
            )

            SwitchRow(
                title: "Menu Bar Countdown",
                hint: "Shows the remaining countdown seconds next to the PromptQuiet icon in your top menu bar.",
                isOn: Binding(
                    get: { controller.settings.showCountdownInMenuBar },
                    set: { controller.setShowCountdownInMenuBar($0) }
                )
            )

            SwitchRow(
                title: "Launch at Login",
                hint: "Starts PromptQuiet automatically in the top menu bar when you log in to macOS.",
                isOn: Binding(
                    get: { controller.launchAtLogin },
                    set: { controller.setLaunchAtLogin($0) }
                )
            )

            SwitchRow(
                title: "Stop Dock Bouncing",
                hint: "Stops vertical Dock icon jumping while notifications are paused, and restores normal Dock jumping as soon as notifications turn back on.",
                isOn: Binding(
                    get: { controller.settings.suppressDockBouncing },
                    set: { controller.setSuppressDockBouncing($0) }
                )
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
    }

    private var footerSection: some View {
        HStack {
            if controller.isSuppressing && !controller.isManuallyPaused {
                HoverTextButton(
                    title: "Resume Now",
                    color: accentGreen,
                    font: .system(size: 13, weight: .medium)
                ) {
                    controller.resumeNow()
                }
                .hoverTooltip("Immediately turn notifications back on and cancel the active countdown.")
            } else {
                HoverTextButton(title: "Reset Daemon") {
                    controller.forceResumeNotificationCenter()
                }
                .hoverTooltip("Safety recovery: immediately sends SIGCONT to NotificationCenter and stops any active stream.")
            }

            Spacer()

            HoverTextButton(title: "Quit") {
                controller.quitApp()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func tooltipCard(payload: TooltipPayload, in proxy: GeometryProxy) -> some View {
        let targetRect = proxy[payload.anchor]
        let tooltipWidth: CGFloat = 264
        let halfW = tooltipWidth / 2
        let centerX = min(max(targetRect.midX, halfW + 12), bubbleWidth - halfW - 12)
        let showBelow = targetRect.minY < 130

        Color.clear
            .frame(width: tooltipWidth, height: 0)
            .overlay(alignment: showBelow ? .top : .bottom) {
                Text(payload.text)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(width: tooltipWidth, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.98))
                            .shadow(color: .black.opacity(0.24), radius: 8, y: 3)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.14), lineWidth: 0.75)
                    )
            }
            .position(
                x: centerX,
                y: showBelow ? targetRect.maxY + 6 : targetRect.minY - 6
            )
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    private var statusDotColor: Color {
        switch controller.state {
        case .manuallyPaused:
            return .purple
        case .typingPaused, .postSendPaused:
            return accentGreen
        case .idle:
            if !controller.isAccessibilityTrusted { return .orange }
            return controller.settings.isEnabled ? accentGreen : .secondary
        }
    }

    private var statusTextColor: Color {
        switch controller.state {
        case .manuallyPaused:
            return .purple
        case .typingPaused, .postSendPaused:
            return accentGreen
        case .idle:
            return controller.isAccessibilityTrusted ? .secondary : .orange
        }
    }

    private var compactStatusText: String {
        switch controller.state {
        case .manuallyPaused(let expiresAt):
            if expiresAt != nil, let formatted = controller.formattedRemainingTime {
                return "Focus · \(formatted)"
            }
            return "Insane Focus"
        case .typingPaused:
            if let seconds = controller.remainingSeconds {
                return "Quiet · \(seconds)s"
            }
            return "Quiet"
        case .postSendPaused:
            if let seconds = controller.remainingSeconds {
                return "Sent · \(seconds)s"
            }
            return "Sent"
        case .idle:
            if !controller.isAccessibilityTrusted {
                return "Accessibility Needed"
            }
            return controller.settings.isEnabled ? "Ready" : "Paused"
        }
    }

    private func submitCustomBundleID() {
        controller.addCustomBundleIdentifier(customBundleInput)
        customBundleInput = ""
        isAddingCustomApp = false
    }
}
