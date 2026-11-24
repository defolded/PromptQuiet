import SwiftUI

@main
struct PromptQuietMain: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(controller: controller)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: controller.menuBarSymbolName)
                if controller.settings.showCountdownInMenuBar,
                   let seconds = controller.remainingSeconds {
                    Text("\(seconds)s")
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
