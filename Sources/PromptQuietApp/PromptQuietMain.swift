import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appController = AppController()
        let statusController = StatusBarController(controller: appController)
        appController.onRequestCloseMenu = { [weak statusController] in
            statusController?.closePanel()
        }
        self.controller = appController
        self.statusBarController = statusController
    }
}

@main
enum PromptQuietMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = MainActor.assumeIsolated { AppDelegate() }
        app.delegate = delegate
        app.run()
    }
}
