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
    @MainActor
    private static var retainedDelegate: AppDelegate?

    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let delegate = AppDelegate()
            retainedDelegate = delegate
            app.delegate = delegate
            withExtendedLifetime(delegate) {
                app.run()
            }
        }
    }
}
