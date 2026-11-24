import PromptQuietCore
import SwiftUI

private let accentGreen = Color(red: 0.16, green: 0.80, blue: 0.25)

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

private struct RingGaugeView: View {
    let progress: Double
    let iconSystemName: String?
    let centerText: String?
    let label: String
    let ringColor: Color
    var onTap: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        let gauge = ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.11), lineWidth: 6.5)

            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 6.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: progress)

            VStack(spacing: 3) {
                if let centerText {
                    Text(centerText)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                } else if let iconSystemName {
                    Image(systemName: iconSystemName)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.primary.opacity(0.85))
                }

                Text(label)
                    .font(.system(size: 9.5, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 74, height: 74)
        .scaleEffect(onTap != nil && isHovering ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovering)

        if let onTap {
            Button(action: onTap) {
                gauge
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
        } else {
            gauge
        }
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
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13.5))
                .foregroundStyle(.primary.opacity(0.9))
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
    let value: Int
    let sliderRange: ClosedRange<Double>
    let clampedRange: ClosedRange<Int>
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.9))

                Spacer()

                HStack(spacing: 6) {
                    HoverTextButton(title: "−", color: .secondary, font: .system(size: 14, weight: .medium)) {
                        onChange(max(clampedRange.lowerBound, value - 1))
                    }
                    .frame(width: 16)

                    Text("\(value)s")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 32, alignment: .center)

                    HoverTextButton(title: "+", color: .secondary, font: .system(size: 14, weight: .medium)) {
                        onChange(min(clampedRange.upperBound, value + 1))
                    }
                    .frame(width: 16)
                }
            }

            MinimalSlider(
                value: Binding(
                    get: { Double(min(max(value, Int(sliderRange.lowerBound)), Int(sliderRange.upperBound))) },
                    set: { onChange(Int($0.rounded())) }
                ),
                range: sliderRange,
                accentColor: accentGreen
            )
        }
    }
}

private struct EnginePillPicker: View {
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
                                .fill(isSelected ? Color.white.opacity(0.85) : Color.clear)
                                .shadow(color: isSelected ? .black.opacity(0.08) : .clear, radius: 1.5, y: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.09))
        )
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
            heroSection
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
    }

    private var hairlineDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }

    private var heroSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 22) {
                RingGaugeView(
                    progress: statusRingProgress,
                    iconSystemName: statusRingIcon,
                    centerText: nil,
                    label: statusRingLabel,
                    ringColor: statusRingColor,
                    onTap: {
                        if controller.isSuppressing {
                            controller.resumeNow()
                        } else {
                            controller.toggleManualPause()
                        }
                    }
                )

                RingGaugeView(
                    progress: typingRingProgress,
                    iconSystemName: typingRingCenterText == nil ? "keyboard" : nil,
                    centerText: typingRingCenterText,
                    label: typingRingLabel,
                    ringColor: accentGreen
                )

                RingGaugeView(
                    progress: sendRingProgress,
                    iconSystemName: sendRingCenterText == nil ? "paperplane" : nil,
                    centerText: sendRingCenterText,
                    label: sendRingLabel,
                    ringColor: accentGreen
                )
            }

            if !controller.isAccessibilityTrusted {
                Button {
                    controller.grantAccessibilityPermission()
                } label: {
                    Label("Grant Accessibility Access", systemImage: "hand.raised.fill")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.orange.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }

            if let error = controller.backendError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
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
        .padding(.vertical, 12)
    }

    private var timersSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            TimerSliderRow(
                title: "Typing Pause",
                value: controller.settings.typingPauseSeconds,
                sliderRange: 5...120,
                clampedRange: PromptQuietSettings.typingPauseRange
            ) { newValue in
                controller.setTypingPauseSeconds(newValue)
            }

            TimerSliderRow(
                title: "After Prompt Sent",
                value: controller.settings.postSendPauseSeconds,
                sliderRange: 1...30,
                clampedRange: PromptQuietSettings.postSendPauseRange
            ) { newValue in
                controller.setPostSendPauseSeconds(newValue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SwitchRow(
                title: "Auto-Silence Typing",
                isOn: Binding(
                    get: { controller.settings.isEnabled },
                    set: { controller.setEnabled($0) }
                )
            )

            SwitchRow(
                title: "Menu Bar Countdown",
                isOn: Binding(
                    get: { controller.settings.showCountdownInMenuBar },
                    set: { controller.setShowCountdownInMenuBar($0) }
                )
            )

            SwitchRow(
                title: "Launch at Login",
                isOn: Binding(
                    get: { controller.launchAtLogin },
                    set: { controller.setLaunchAtLogin($0) }
                )
            )

            HStack {
                Text("Engine")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.primary.opacity(0.9))
                Spacer()
                EnginePillPicker(
                    selection: Binding(
                        get: { controller.settings.suppressionMode },
                        set: { controller.setSuppressionMode($0) }
                    )
                )
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var footerSection: some View {
        HStack {
            if controller.isSuppressing {
                HoverTextButton(
                    title: "Resume Now",
                    color: accentGreen,
                    font: .system(size: 13, weight: .medium)
                ) {
                    controller.resumeNow()
                }
            } else {
                HoverTextButton(title: "Reset Daemon") {
                    controller.forceResumeNotificationCenter()
                }
            }

            Spacer()

            HoverTextButton(title: "Quit") {
                controller.quitApp()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
    }

    // MARK: - Ring Gauge Derived State

    private var statusRingProgress: Double {
        if !controller.isAccessibilityTrusted { return 0.25 }
        if !controller.settings.isEnabled { return 0.08 }
        switch controller.state {
        case .idle:
            return 0.25
        case .typingPaused, .postSendPaused, .manuallyPaused:
            return 1.0
        }
    }

    private var statusRingIcon: String {
        if !controller.isAccessibilityTrusted { return "hand.raised" }
        if !controller.settings.isEnabled { return "bell.slash" }
        switch controller.state {
        case .idle:
            return "bell"
        case .typingPaused, .postSendPaused:
            return "bell.slash.fill"
        case .manuallyPaused:
            return "pause.fill"
        }
    }

    private var statusRingLabel: String {
        if !controller.isAccessibilityTrusted { return "PERMS" }
        if !controller.settings.isEnabled { return "OFF" }
        switch controller.state {
        case .idle:
            return "READY"
        case .typingPaused, .postSendPaused:
            return "QUIET"
        case .manuallyPaused:
            return "PAUSED"
        }
    }

    private var statusRingColor: Color {
        if !controller.isAccessibilityTrusted { return .orange }
        if !controller.settings.isEnabled { return Color.primary.opacity(0.25) }
        return accentGreen
    }

    private var typingRingProgress: Double {
        if case .typingPaused = controller.state, let remaining = controller.remainingSeconds {
            return Double(remaining) / Double(max(controller.settings.typingPauseSeconds, 1))
        }
        return min(Double(controller.settings.typingPauseSeconds) / 60.0, 1.0)
    }

    private var typingRingCenterText: String? {
        if case .typingPaused = controller.state, let remaining = controller.remainingSeconds {
            return "\(remaining)s"
        }
        return nil
    }

    private var typingRingLabel: String {
        if case .typingPaused = controller.state {
            return "TYPING"
        }
        return "\(controller.settings.typingPauseSeconds)S IDLE"
    }

    private var sendRingProgress: Double {
        if case .postSendPaused = controller.state, let remaining = controller.remainingSeconds {
            return Double(remaining) / Double(max(controller.settings.postSendPauseSeconds, 1))
        }
        return min(Double(controller.settings.postSendPauseSeconds) / 30.0, 1.0)
    }

    private var sendRingCenterText: String? {
        if case .postSendPaused = controller.state, let remaining = controller.remainingSeconds {
            return "\(remaining)s"
        }
        return nil
    }

    private var sendRingLabel: String {
        if case .postSendPaused = controller.state {
            return "SENDING"
        }
        return "\(controller.settings.postSendPauseSeconds)S SEND"
    }

    private func submitCustomBundleID() {
        controller.addCustomBundleIdentifier(customBundleInput)
        customBundleInput = ""
        isAddingCustomApp = false
    }
}
