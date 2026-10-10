import SwiftUI
import AppKit

@main
struct FanControlApp: App {
    @StateObject private var controller = FanController()

    var body: some Scene {
        WindowGroup("风扇控制") {
            ContentView(ctl: controller)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1160, height: 870)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("交还 BIOS 控制") { controller.returnToBIOS() }
                Button("立即刷新") { controller.refresh() }
            }
        }
    }
}
