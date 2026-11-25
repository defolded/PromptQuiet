import AppKit
import Combine
import SwiftUI

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SizingHostingView<Content: View>: NSHostingView<Content> {
    var onIntrinsicSizeInvalidated: (@MainActor () -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        let callback = onIntrinsicSizeInvalidated
        Task { @MainActor in
            callback?()
        }
    }
}

/// Manages the native top menu bar `NSStatusItem` and a borderless transparent `NSPanel`
/// hosting `MenuBarView`, avoiding SwiftUI `MenuBarExtra(.window)` top/bottom box artifacts.
@MainActor
final class StatusBarController: NSObject {
    private static let panelWidth: CGFloat = 328

    private let controller: AppController
    private let statusItem: NSStatusItem
    private let panel: KeyablePanel
    private let hostingView: SizingHostingView<MenuBarView>

    private var cancellables: Set<AnyCancellable> = []
    private var globalMouseMonitor: Any?
    private var localKeyMonitor: Any?
    private var spaceObserver: NSObjectProtocol?
    private var isPanelVisible = false
    private var anchoredOriginX: CGFloat?
    private var anchoredTopY: CGFloat?
    private var anchoredVisibleMinY: CGFloat = 8

    init(controller: AppController) {
        self.controller = controller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        self.panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.hostingView = SizingHostingView(rootView: MenuBarView(controller: controller))

        super.init()

        configurePanel()
        configureStatusItem()
        bindControllerUpdates()
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovable = false
        panel.hidesOnDeactivate = false

        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.onIntrinsicSizeInvalidated = { [weak self] in
            guard let self, self.isPanelVisible else { return }
            self.positionAndResizePanel(reanchor: false)
        }
        panel.contentView = hostingView
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePanel(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusButton()
    }

    private func bindControllerUpdates() {
        controller.onStatusBarUpdate = { [weak self] in
            self?.updateStatusButton()
        }

        Publishers.CombineLatest4(
            controller.$state,
            controller.$remainingSeconds,
            controller.$settings,
            controller.$isAccessibilityTrusted
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _, _, _ in
            self?.updateStatusButton()
        }
        .store(in: &cancellables)
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .medium)
        let image = NSImage(
            systemSymbolName: controller.menuBarSymbolName,
            accessibilityDescription: "PromptQuiet"
        )?.withSymbolConfiguration(symbolConfig)
        image?.isTemplate = true
        button.image = image

        if controller.settings.showCountdownInMenuBar,
           let countdownText = controller.menuBarCountdownText {
            statusItem.length = 46
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
            ]
            button.attributedTitle = NSAttributedString(string: " \(countdownText)", attributes: attributes)
            button.imagePosition = .imageLeading
        } else {
            statusItem.length = NSStatusItem.variableLength
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    @objc private func togglePanel(_ sender: AnyObject?) {
        if isPanelVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        isPanelVisible = true
        controller.isMenuPanelOpen = true
        controller.refreshPermissions()

        positionAndResizePanel(reanchor: true)
        panel.makeKeyAndOrderFront(nil)
        // Prevent auto-focusing the custom bundle ID TextField when the menu opens.
        panel.makeFirstResponder(nil)

        installDismissMonitors()
    }

    func closePanel() {
        guard isPanelVisible else { return }
        isPanelVisible = false
        anchoredOriginX = nil
        anchoredTopY = nil
        controller.isMenuPanelOpen = false
        panel.orderOut(nil)
        removeDismissMonitors()
    }

    private func positionAndResizePanel(reanchor: Bool) {
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let size = NSSize(width: Self.panelWidth, height: max(100, ceil(fitting.height)))

        let originX: CGFloat
        let topY: CGFloat
        let visibleMinY: CGFloat

        if reanchor || anchoredOriginX == nil || anchoredTopY == nil {
            guard let button = statusItem.button,
                  let buttonWindow = button.window else {
                return
            }

            let buttonRectInWindow = button.convert(button.bounds, to: nil)
            let buttonScreenRect = buttonWindow.convertToScreen(buttonRectInWindow)

            let targetScreen = buttonWindow.screen ?? NSScreen.main
            let visibleFrame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

            topY = buttonScreenRect.minY - 2
            let preferredX = round(buttonScreenRect.midX - Self.panelWidth / 2)
            let maxX = visibleFrame.maxX - size.width - 8
            let minX = visibleFrame.minX + 8
            originX = max(minX, min(preferredX, maxX))
            visibleMinY = visibleFrame.minY

            anchoredOriginX = originX
            anchoredTopY = topY
            anchoredVisibleMinY = visibleMinY

            let arrowX = min(max(buttonScreenRect.midX - originX, 36), Self.panelWidth - 36)
            if abs(controller.popoverArrowX - arrowX) > 0.5 {
                controller.popoverArrowX = arrowX
            }
        } else {
            originX = anchoredOriginX!
            topY = anchoredTopY!
            visibleMinY = anchoredVisibleMinY
        }

        let originY = max(visibleMinY + 8, topY - size.height)
        let newFrame = NSRect(origin: NSPoint(x: originX, y: originY), size: size)
        let currentFrame = panel.frame
        if abs(currentFrame.origin.x - newFrame.origin.x) > 0.5 ||
            abs(currentFrame.origin.y - newFrame.origin.y) > 0.5 ||
            abs(currentFrame.size.width - newFrame.size.width) > 0.5 ||
            abs(currentFrame.size.height - newFrame.size.height) > 0.5 {
            panel.setFrame(newFrame, display: true)
        }
    }

    private func installDismissMonitors() {
        removeDismissMonitors()

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePanel()
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                Task { @MainActor [weak self] in
                    self?.closePanel()
                }
                return nil
            }
            return event
        }

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePanel()
            }
        }
    }

    private func removeDismissMonitors() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
    }
}
