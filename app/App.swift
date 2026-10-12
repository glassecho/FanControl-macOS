import SwiftUI
import AppKit

/// 全局单例持有者。
/// 菜单栏项（AppKit 侧）和主窗口（SwiftUI 侧）必须共用**同一个** FanController，
/// 所以它不能是 App 结构体里的 `@StateObject` —— 那样 AppDelegate 够不着。
enum AppCore {
    static let controller = FanController()
}

/// 把 SwiftUI 的 `openWindow` 动作交给 `MainWindow`。
///
/// 主窗口一旦被**真正销毁**（而不是隐藏），`makeKeyAndOrderFront` 就无能为力了 ——
/// 只有 SwiftUI 能把它重建出来，而这个能力藏在 View 的环境里，
/// AppDelegate（AppKit 侧）拿不到，所以在这里取一次存起来备用。
private struct OpenWindowBridge: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { MainWindow.capture(openWindow) }
    }
}

/// 菜单命令 —— 顺便承担一个**关键职责**：注入 `openWindow`。
///
/// `OpenWindowBridge` 挂在窗口内容上，只有窗口出现过才会执行；但
/// **开机自启（登录项）启动时主窗口可能压根没被创建**（用户实测到的正是这个），
/// 那时 `openWindowAction` 永远是 nil，「点图标 / 点打开主窗口」自然都没反应。
/// `Commands` 在 app 启动构建菜单时就会求值 —— 比窗口更早，也更可靠。
struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L.openMainWindow) { MainWindow.show() }
                .keyboardShortcut("n", modifiers: .command)
                .onAppear { MainWindow.capture(openWindow) }
        }
        CommandGroup(after: .appInfo) {
            Button(L.headerReturnBIOS) { AppCore.controller.returnToBIOS() }
            Button(L.refreshTip) { AppCore.controller.refresh() }
        }
    }
}

@main
struct FanControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(L.appName, id: "main") {
            ContentView(ctl: AppCore.controller)
                .background(OpenWindowBridge())
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1160, height: 870)
        .commands { AppCommands() }

        // 菜单栏项不是 Scene —— 由 AppDelegate 直接建 NSStatusItem（见 StatusItem.swift）。
        // SwiftUI 的 MenuBarExtra 只能渲染「一个图标 + 一段文字」，做不了多项图标。
    }
}
