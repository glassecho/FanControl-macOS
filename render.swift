// 离屏渲染工具：把界面渲染成 PNG，用于自检与预览。
//
//   swiftc -O -parse-as-library -target x86_64-apple-macos13.0 -sdk "$(xcrun --show-sdk-path)" \
//     -o /tmp/render app/L.swift app/Model.swift app/Views.swift render.swift \
//     -framework SwiftUI -framework AppKit -framework Foundation
//
// 用 FANCTL_PATH 指向未安装的新版 helper 就能预览新字段。
// 用 FANCONTROL_LANG=en / zh 切换界面语言：
//   FANCONTROL_LANG=zh /tmp/render preview     # 中文全套 01–08
//   FANCONTROL_LANG=en /tmp/render preview     # 英文 09–10（给 README 的 English 段用）
//
// ⚠️ 输出文件名不要随便改。
// preview/ 里的 01–04 已经发到 GitHub，并被贴吧 / 各平台的帖子用
// `cdn.jsdelivr.net/gh/<user>/FanControl-macOS@main/preview/xx.png` 引用过。
// 改名字 = 那些帖子里的图全部变成裂图。要加新图只能往后编号。
import SwiftUI
import AppKit

@discardableResult
@MainActor
func shoot<V: View>(_ v: V, _ dir: String, _ name: String, w: CGFloat, h: CGFloat) -> Bool {
    let view = v.frame(width: w, height: h).preferredColorScheme(.dark)
    let r = ImageRenderer(content: view)
    r.scale = 2.0
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("渲染失败: \(name)\n".data(using: .utf8)!)
        return false
    }
    try? png.write(to: URL(fileURLWithPath: dir + "/" + name))
    print("  \(name)  \(rep.pixelsWide)x\(rep.pixelsHigh)")
    return true
}

/// 让截图里的手动模式看起来「有人在用」：勾上所有可控通道，各给一个不同的占空比。
@MainActor
func populateManual(_ ctl: FanController) {
    guard let s = ctl.snapshot else { return }
    let pump = s.pumpChannel
    let adjustable = s.fans.filter { $0.ch != pump && $0.controllable }
    ctl.selectedFans = Set(adjustable.map { $0.ch })
    let presets: [Double] = [35, 45, 55, 60, 40, 50, 30, 65]
    var d: [Int: Double] = [:]
    for (i, f) in adjustable.enumerated() { d[f.ch] = presets[i % presets.count] }
    ctl.manualDuty = d
}

@main
struct RenderMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        let ctl = FanController()

        // 等后台 refresh()（read + sys，后者有 400ms 采样窗口）回填到主线程
        RunLoop.main.run(until: Date().addingTimeInterval(3.5))

        if let s = ctl.snapshot {
            FileHandle.standardError.write("风扇 \(s.fans.count) 个，传感器 \(s.sensors.count) 个\n".data(using: .utf8)!)
        } else {
            FileHandle.standardError.write("警告：未取到风扇状态\n".data(using: .utf8)!)
        }
        if let sy = ctl.sys {
            FileHandle.standardError.write("CPU \(sy.cpu.cores) 核 \(sy.cpu.total)%，进程 \(sy.procs.count) 条，卷 \(sy.disk.count) 个\n".data(using: .utf8)!)
        } else {
            FileHandle.standardError.write("警告：未取到系统监控数据\n".data(using: .utf8)!)
        }

        let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp"
        let isEN = (L.lang == .en)
        print("渲染到 \(outDir)（语言：\(isEN ? "en" : "zh")）：")

        // ── 英文：只出 2 张，给 README 的 English 段用 ────────────────────
        // 中英各出一整套会把仓库体积翻倍，而且英文读者只需要看清「界面长什么样」。
        if isEN {
            ctl.mode = .standard
            ctl.minDuty = ControlMode.standard.minDuty
            shoot(ContentView(ctl: ctl), outDir, "09-control-en.png", w: 1160, h: 870)
            shoot(ContentView(ctl: ctl, startPage: 1, scrollMonitor: false),
                  outDir, "10-monitor-en.png", w: 1160, h: 870)
            return
        }

        // ── 中文：01–04 名字沿用仓库里已有的，覆盖更新 ────────────────────
        // 已发出去的 jsDelivr 链接走 @main 分支，重推后会自动跟着变新。

        ctl.mode = .standard
        ctl.minDuty = ControlMode.standard.minDuty
        shoot(ContentView(ctl: ctl), outDir, "01-control-standard.png", w: 1160, h: 870)

        ctl.mode = .manual
        ctl.minDuty = ControlMode.manual.minDuty
        populateManual(ctl)
        shoot(ContentView(ctl: ctl), outDir, "02-control-manual.png", w: 1160, h: 870)

        ctl.mode = .custom
        ctl.minDuty = ControlMode.custom.minDuty
        shoot(ContentView(ctl: ctl), outDir, "03-control-custom-curve.png", w: 1160, h: 870)

        ctl.mode = .standard
        ctl.minDuty = ControlMode.standard.minDuty
        shoot(ContentView(ctl: ctl).helpCard.padding(16).background(Theme.bg),
              outDir, "04-help-panel.png", w: 470, h: 398)

        // ── 05–08：1.4.1 新增的截图 ──────────────────────────────────────

        shoot(ContentView(ctl: ctl, startPage: 1, scrollMonitor: false),
              outDir, "05-monitor.png", w: 1160, h: 870)

        ctl.enabledPanels = Set(PanelKind.allCases)
        shoot(MonitorPanels(ctl: ctl).padding(14).background(Theme.bg),
              outDir, "06-monitor-panels.png", w: 880, h: 820)

        // 菜单栏弹出面板（点状态栏图标出来的那个）
        // 1.4.1 起底部多了「开机自启」一行，高度从 540 提到 620
        shoot(MenuBarPanel(ctl: ctl), outDir, "07-menubar-panel.png", w: 326, h: 620)

        // 菜单栏上那一条长什么样 —— 用同一套零件离屏模拟
        // （真正的状态栏由 AppKit 的 NSStatusItem 画，渲染器抓不到）
        shoot(StatusBarPreview(ctl: ctl), outDir, "08-menubar-look.png", w: 420, h: 30)
    }
}

/// 模拟系统菜单栏外观，用来预览「多个项目各自带图标 + 数值」的排版效果。
/// 真机上由 StatusItemController 用 attributedTitle 画在 NSStatusItem 上。
struct StatusBarPreview: View {
    @ObservedObject var ctl: FanController

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                if ctl.menuBarItemList.isEmpty {
                    Image(systemName: "fanblades.fill")
                } else {
                    ForEach(ctl.menuBarItemList) { item in
                        HStack(spacing: 3) {
                            Image(systemName: item.symbol)
                            if let t = menuBarText(ctl, item) { Text(t) }
                        }
                    }
                }
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.30, green: 0.28, blue: 0.40),
                                    Color(red: 0.22, green: 0.24, blue: 0.36)],
                           startPoint: .leading, endPoint: .trailing))
    }
}
