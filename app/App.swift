import SwiftUI
import AppKit

/// 全局单例持有者。
/// 菜单栏项（AppKit 侧）和主窗口（SwiftUI 侧）必须共用**同一个** FanController，
/// 所以它不能是 App 结构体里的 `@StateObject` —— 那样 AppDelegate 够不着。
enum AppCore {
    static let controller = FanController()
}

@main
struct FanControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private var controller: FanController { AppCore.controller }

    var body: some Scene {
        WindowGroup("风扇控制", id: "main") {
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

        // 菜单栏项不是 Scene —— 由 AppDelegate 直接建 NSStatusItem（见 StatusItem.swift）。
        // SwiftUI 的 MenuBarExtra 只能渲染「一个图标 + 一段文字」，做不了多项图标。
    }
}
