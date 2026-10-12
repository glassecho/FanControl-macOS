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

/// 主窗口不真正关闭、只是隐藏（见 AppDelegate），所以这里总能把它叫回来。
enum MainWindow {
    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.title == L.appName }) {
            w.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - App 生命周期

/// 菜单栏应用的两个特殊之处：
/// 1. 关掉主窗口 ≠ 退出 —— 只是隐藏，否则菜单栏面板上的「打开主窗口」就没东西可开了
/// 2. 点程序坞图标要把隐藏的窗口叫回来
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        StatusItemController.shared.attach(AppCore.controller)
        adoptMainWindow(attempt: 0)
    }

    /// SwiftUI 的 WindowGroup 窗口是异步创建的，所以要轮几次才能抓到
    private func adoptMainWindow(attempt: Int) {
        if let w = NSApp.windows.first(where: { $0.title == L.appName }) {
            w.delegate = self
            w.isReleasedWhenClosed = false
            return
        }
        guard attempt < 12 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.adoptMainWindow(attempt: attempt + 1)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindow.show() }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
