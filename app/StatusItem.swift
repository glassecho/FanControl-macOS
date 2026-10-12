import SwiftUI
import AppKit
import Combine

// MARK: - 菜单栏（状态栏）常驻项

/// 为什么不用 SwiftUI 的 `MenuBarExtra`？
///
/// 实测（四种写法都试过）它的 label 只会取**第一个 `Image`** 当按钮图标、
/// **第一个 `Text`** 当标题，其余内容被静默丢弃：
///
/// | label 写法 | 实际渲染出来 |
/// |---|---|
/// | `ForEach { HStack { Image; Text } }` 4 项 | 只有第 1 项的图标 + 数值 |
/// | 拼成单个 `Text(Image(...) + Text(...))` | 全部文字，但图标全丢 |
/// | 同上 + `.fixedSize()` | 仍然只有第 1 项 |
/// | `ForEach { Label(t, systemImage:) }` | 只有第 1 项的图标，文字全丢 |
///
/// 而用户要的是「多个项目各自带图标 + 数值」，所以这里直接拿 `NSStatusItem`，
/// 用 `attributedTitle` 把 SF Symbol 附件和文字一起画出来 —— 探针实测可正常渲染。
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private weak var ctl: FanController?
    private var cancellable: AnyCancellable?
    /// `.transient` 的弹窗会在点击按钮时先自动关闭，紧接着 action 又把它打开 →
    /// 表现为「点一下闪一下」。用关闭时间做个小阻尼。
    private var lastClose = Date.distantPast

    private override init() { super.init() }

    /// 只装一次。重复调用无害。
    func attach(_ ctl: FanController) {
        guard statusItem == nil else { return }
        self.ctl = ctl

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = item.button {
            b.target = self
            b.action = #selector(togglePopover)
            b.imagePosition = .noImage
            b.toolTip = L.appName
        }
        statusItem = item

        popover.behavior = .transient
        popover.animates = false
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPanel(ctl: ctl, openMain: { [weak self] in
                MainWindow.show()
                self?.popover.performClose(nil)
            }))

        NotificationCenter.default.addObserver(
            self, selector: #selector(popoverDidClose),
            name: NSPopover.didCloseNotification, object: popover)

        // FanController 每次刷新都会 objectWillChange，跟着重画标题
        cancellable = ctl.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.render() }
        }

        render()

        // 调试钩子：FANCONTROL_DEBUG_PANEL=1 时启动后自动弹出面板，用于离屏截图自检
        if ProcessInfo.processInfo.environment["FANCONTROL_DEBUG_PANEL"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.togglePopover()
            }
        }
    }

    // MARK: 标题渲染

    func render() {
        guard let b = statusItem?.button, let ctl = ctl else { return }
        let items = ctl.menuBarItemList

        // 一项都没勾时也要留个图标 —— 否则菜单栏点不到，设置就再也打不开了
        guard !items.isEmpty else {
            b.attributedTitle = NSAttributedString(string: "")
            b.image = symbol("fanblades.fill", size: 13)
            return
        }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let s = NSMutableAttributedString()
        for (i, k) in items.enumerated() {
            if i > 0 { s.append(NSAttributedString(string: "   ")) }
            if let img = symbol(k.symbol) {
                let att = NSTextAttachment()
                att.image = img
                s.append(NSAttributedString(attachment: att))
            }
            if let t = menuBarText(ctl, k) {
                s.append(NSAttributedString(string: " " + t, attributes: [.font: font]))
            }
        }
        b.image = nil
        b.attributedTitle = s
    }

    private func symbol(_ name: String, size: CGFloat = 10.5) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else { return nil }
        img.isTemplate = true
        return img
    }

    // MARK: 弹窗

    @objc private func togglePopover() {
        guard let b = statusItem?.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        // 刚被自动关掉的那种「点按钮」不算，避免闪一下又开
        if Date().timeIntervalSince(lastClose) < 0.25 { return }

        ctl?.refresh()
        popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func popoverDidClose() { lastClose = Date() }
}

// MARK: - 主窗口

/// 主窗口正常不真正关闭、只是隐藏（见 AppDelegate），所以这里总能把它叫回来。
///
/// ⚠️ 前提是 `AppDelegate` 已经**认领**了这个窗口（接管了它的关闭行为）。
/// 这里原来是固定 3 秒轮询认领，会漏 —— SwiftUI 建窗的时机并不确定，
/// 而 `applicationDidFinishLaunching` 里 `attach()` 触发的首屏构建可能把主线程占住，
/// 于是轮询可能全部在窗口出现之前跑完。漏掉的后果是：用户点红叉**真的关掉了窗口**，
/// 此后 `makeKeyAndOrderFront` 再也救不回来，表现为「点菜单栏 / 程序坞都没反应」。
/// 所以这里多一道保险：窗口真的没了，就请 SwiftUI 重建一个。
enum MainWindow {
    /// SwiftUI 的 `openWindow(id:)` 动作。
    ///
    /// 注入点有两个，缺一不可（都在 App.swift）：`OpenWindowBridge` 在窗口出现时注入，
    /// `AppCommands` 在 app 启动构建菜单时注入 —— 开机自启场景下窗口可能压根没被创建，
    /// 那时只能靠后者。
    static var openWindowAction: ((String) -> Void)?

    static func capture(_ action: OpenWindowAction) {
        openWindowAction = { id in action(id: id) }
    }

    static let sceneID = "main"

    /// 主窗口的识别。**不只看标题** —— 标题会随界面语言变，不该把
    /// 「窗口能不能被找到」绑死在文案上。按可靠性依次尝试。
    static func isMain(_ w: NSWindow) -> Bool {
        // SwiftUI 给窗口设的 identifier，形如 `main-AppWindow-1`
        if (w.identifier?.rawValue ?? "").hasPrefix(sceneID + "-AppWindow-") { return true }
        // SwiftUI 的普通窗口类（状态栏项是 NSStatusBarWindow、面板是 _NSPopoverWindow）
        if w.className == "SwiftUI.AppKitWindow" { return true }
        // 兜底：标题
        return w.title == L.appName
    }

    static func find() -> NSWindow? { NSApp.windows.first(where: isMain) }

    /// 上次请求重建窗口的时间 —— 防止窗口还没建好时连点，一次开出一堆。
    private static var lastRebuild = Date.distantPast

    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = find() {
            AppDelegate.shared?.adopt(w)          // 顺手补一次认领（可能之前漏了）
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
            return
        }
        // 窗口已被 SwiftUI 释放 —— 只有 SwiftUI 能把它重建出来
        let now = Date()
        guard now.timeIntervalSince(lastRebuild) > 0.6 else { return }
        lastRebuild = now
        openWindowAction?(sceneID)
    }
}

// MARK: - App 生命周期

/// 菜单栏应用的两个特殊之处：
/// 1. 关掉主窗口 ≠ 退出 —— 只是隐藏，否则菜单栏面板上的「打开主窗口」就没东西可开了
/// 2. 点程序坞图标要把隐藏的窗口叫回来
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    /// 供 `MainWindow.show()` 在找到窗口时顺手补认领。
    static private(set) var shared: AppDelegate?

    /// 已经认领过的窗口，避免每个事件循环都重复走一遍检查。
    private weak var adoptedWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        StatusItemController.shared.attach(AppCore.controller)

        // 主窗口出现的时机不确定（SwiftUI 异步建窗；主线程还可能正被首屏数据读取占着），
        // 所以两条腿走路：通知负责「窗口一冒头就认领」，轮询负责兜底。
        //
        // 注意：AppKit **没有**「窗口变可见」通知 —— `NSWindowDidBecomeVisibleNotification`
        // 并不存在（只有 DidBecomeKey / DidBecomeMain）。所以再补一个
        // `NSApplication.didUpdate`：它每个事件循环都发一次，窗口一出现必然被抓到。
        let nc = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification,
                     NSWindow.didBecomeMainNotification,
                     NSApplication.didUpdateNotification] {
            nc.addObserver(self, selector: #selector(windowAppeared), name: name, object: nil)
        }
        adoptMainWindow(attempt: 0)

        // 兜底：**开机自启（登录项）启动时 SwiftUI 有可能不建主窗口** ——
        // 那时 `NSApp.windows` 里只剩状态栏项，点图标、点「打开主窗口」全都石沉大海。
        // 这里延迟检查一次，没有就请 SwiftUI 建一个出来。
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if MainWindow.find() == nil { MainWindow.show() }
        }
    }

    @objc private func windowAppeared(_ note: Notification) {
        // didUpdate 的 object 是 NSApplication（没有具体窗口），这时自己找一次
        guard let w = (note.object as? NSWindow) ?? MainWindow.find() else { return }
        adopt(w)
    }

    /// 认领主窗口 —— 接管它的关闭行为（隐藏而非销毁）。幂等，可重复调用。
    func adopt(_ w: NSWindow) {
        guard MainWindow.isMain(w) else { return }
        if adoptedWindow === w && w.delegate === self { return }   // 认领过了，省掉后续检查
        adoptedWindow = w
        if w.delegate !== self { w.delegate = self }
        w.isReleasedWhenClosed = false
    }

    /// 兜底轮询：40 × 0.25s = 10 秒。
    /// 正常情况通知早就认领完了，这里主要防「窗口建得特别晚」。
    private func adoptMainWindow(attempt: Int) {
        if let w = MainWindow.find() { adopt(w); return }
        guard attempt < 40 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.adoptMainWindow(attempt: attempt + 1)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 无脑调一次：窗口在就前置、不在就重建，两种情况都该有反应。
        // 原来只在 `!flag` 时调，而菜单栏 app 的「有没有可见窗口」很容易被
        // 状态栏项（NSStatusBarWindow）干扰 —— 判断失准就等于点了没反应。
        MainWindow.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
