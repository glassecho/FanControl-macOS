// 离屏渲染工具：把界面渲染成 PNG，用于自检与预览。
//
//   swiftc -O -parse-as-library -target x86_64-apple-macos13.0 -sdk "$(xcrun --show-sdk-path)" \
//     -o /tmp/render app/Model.swift app/Views.swift render.swift \
//     -framework SwiftUI -framework AppKit -framework Foundation
//
// 用 FANCTL_PATH 指向未安装的新版 helper 就能预览新字段。
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

@main
struct RenderMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        let ctl = FanController()

        // 等一次 refresh() 回填（1.2 只有 `fanctl read`，很快）
        RunLoop.main.run(until: Date().addingTimeInterval(2.0))

        if let s = ctl.snapshot {
            FileHandle.standardError.write("风扇 \(s.fans.count) 个，传感器 \(s.sensors.count) 个\n".data(using: .utf8)!)
        } else {
            FileHandle.standardError.write("警告：未取到风扇状态\n".data(using: .utf8)!)
        }
        if ctl.gpu == nil {
            FileHandle.standardError.write("提示：没有显卡监控数据（无驱动的显卡不显示显卡卡）\n".data(using: .utf8)!)
        }

        let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp"
        print("渲染到 \(outDir)：")

        // 标准曲线模式（默认）
        ctl.mode = .standard
        ctl.minDuty = ControlMode.standard.minDuty
        shoot(ContentView(ctl: ctl), outDir, "01-control-standard.png", w: 1160, h: 870)

        // 手动模式：每个风扇一个固定占空比滑块
        ctl.mode = .manual
        shoot(ContentView(ctl: ctl), outDir, "02-control-manual.png", w: 1160, h: 870)

        // 自定义曲线：可拖动的控制点
        ctl.mode = .custom
        shoot(ContentView(ctl: ctl), outDir, "03-control-custom-curve.png", w: 1160, h: 870)

        // 说明面板（标题栏 ? 里弹出的那张）
        ctl.mode = .standard
        shoot(ContentView(ctl: ctl).helpCard.padding(14).background(Theme.bg),
              outDir, "04-help-panel.png", w: 458, h: 400)
    }
}
