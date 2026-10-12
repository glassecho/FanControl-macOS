import SwiftUI
import AppKit

// MARK: - 配色

enum Theme {
    static let bg      = Color(red: 0.075, green: 0.082, blue: 0.098)
    static let panel   = Color(red: 0.118, green: 0.129, blue: 0.153)
    static let panel2  = Color(red: 0.157, green: 0.169, blue: 0.196)
    static let stroke  = Color.white.opacity(0.07)
    static let text    = Color(red: 0.91, green: 0.92, blue: 0.94)
    static let dim     = Color(red: 0.55, green: 0.58, blue: 0.63)
    static let accent  = Color(red: 0.36, green: 0.66, blue: 1.00)
    static let green   = Color(red: 0.30, green: 0.80, blue: 0.50)
    static let orange  = Color(red: 1.00, green: 0.68, blue: 0.30)
    static let red     = Color(red: 1.00, green: 0.44, blue: 0.44)
}

// MARK: - 小部件

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke, lineWidth: 1))
            // 背景是圆角矩形（可伸缩），不锁住的话卡片会被同列更高的兄弟撑开
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .textCase(.uppercase)
            .kerning(0.6)
    }
}

struct TempChip: View {
    let label: String
    let value: Double?
    let tint: Color
    /// 附加信息，例如显卡风扇转速
    var extra: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.dim)
            Text(value.map { String(format: "%.0f°C", $0) } ?? "—")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            if let e = extra {
                Text(e)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.dim)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(Theme.panel2))
    }
}

/// 显卡监控用的小指标块：标签 + 主数值 + 可选副数值
struct MetricChip: View {
    let symbol: String
    let label: String
    let value: String
    var sub: String? = nil
    var tint: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.dim)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                if let s = sub {
                    Text(s)
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(Theme.dim)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel2))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.stroke, lineWidth: 1))
    }
}

/// 按温度阈值着色：<65 绿、65–80 橙、>80 红
func tempTint(_ t: Double?) -> Color {
    guard let t = t else { return Theme.dim }
    if t >= 80 { return Theme.red }
    if t >= 65 { return Theme.orange }
    return Theme.green
}

/// 取整显示，缺失显示破折号
func fmt0(_ v: Double?) -> String {
    v.map { String(format: "%.0f", $0) } ?? "—"
}

// MARK: - 模式选择

struct ModeRow: View {
    let mode: ControlMode
    let selected: Bool
    let applied: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Theme.accent : Theme.dim)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(mode.label)
                            .font(.system(size: 13, weight: selected ? .semibold : .regular))
                            .foregroundStyle(Theme.text)
                        if applied {
                            Text(L.svcRunning)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.green)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Theme.green.opacity(0.15)))
                        }
                    }
                    Text(mode.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.dim)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Theme.accent.opacity(0.13) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Theme.accent.opacity(0.45) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 自绘滑块（原生 Slider 在深色面板里风格不统一）

struct DutySlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...60
    var step: Double = 1
    var accent: Color = Theme.accent
    var width: CGFloat = 240

    private let trackH: CGFloat = 6
    private let thumb: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - thumb)
            let frac = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = thumb / 2 + CGFloat(min(max(frac, 0), 1)) * usable

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.panel2)
                    .frame(height: trackH)
                    .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                Capsule()
                    .fill(accent)
                    .frame(width: x, height: trackH)
                Circle()
                    .fill(Theme.panel)
                    .overlay(Circle().stroke(accent, lineWidth: 2))
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .offset(x: x - thumb / 2)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let f = (g.location.x - thumb / 2) / usable
                        let raw = range.lowerBound + Double(min(max(f, 0), 1)) * (range.upperBound - range.lowerBound)
                        value = (raw / step).rounded() * step
                    }
            )
        }
        .frame(width: width, height: 20)
    }
}

// MARK: - 曲线编辑器

/// 曲线绘图区的坐标换算（避免在 ViewBuilder 闭包里声明函数）
struct PlotGeom {
    let padL: CGFloat = 46
    let padR: CGFloat = 18
    let padT: CGFloat = 16
    let padB: CGFloat = 30
    let plotW: CGFloat
    let plotH: CGFloat
    let minTemp: Double
    let maxTemp: Double

    init(size: CGSize, minTemp: Double, maxTemp: Double) {
        self.minTemp = minTemp
        self.maxTemp = maxTemp
        self.plotW = max(1, size.width - 46 - 18)
        self.plotH = max(1, size.height - 16 - 30)
    }

    func px(_ t: Double) -> CGFloat {
        let span = maxTemp - minTemp
        guard span > 0 else { return padL }
        return padL + CGFloat((t - minTemp) / span) * plotW
    }

    func py(_ d: Double) -> CGFloat {
        padT + plotH - CGFloat(d / 100.0) * plotH
    }
}

struct CurveEditor: View {
    @Binding var points: [CurvePoint]
    let editable: Bool
    var currentTemp: Double?
    var minTemp: Double = 30
    var maxTemp: Double = 100

    @State private var dragIndex: Int? = nil

    private let padL: CGFloat = 46
    private let padT: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let g = PlotGeom(size: geo.size, minTemp: minTemp, maxTemp: maxTemp)
            let plotW = g.plotW
            let plotH = g.plotH
            let px = { (t: Double) in g.px(t) }
            let py = { (d: Double) in g.py(d) }

            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    // 横向网格 + 百分比刻度
                    for d in stride(from: 0.0, through: 100.0, by: 25.0) {
                        let yy = py(d)
                        var line = Path()
                        line.move(to: CGPoint(x: padL, y: yy))
                        line.addLine(to: CGPoint(x: padL + plotW, y: yy))
                        ctx.stroke(line, with: .color(Theme.stroke), lineWidth: 1)
                        ctx.draw(Text("\(Int(d))%")
                                    .font(.system(size: 9.5)).foregroundColor(Theme.dim),
                                 at: CGPoint(x: padL - 8, y: yy), anchor: .trailing)
                    }
                    // 纵向网格 + 温度刻度
                    for t in stride(from: 40.0, through: maxTemp, by: 20.0) {
                        let xx = px(t)
                        var line = Path()
                        line.move(to: CGPoint(x: xx, y: padT))
                        line.addLine(to: CGPoint(x: xx, y: padT + plotH))
                        ctx.stroke(line, with: .color(Theme.stroke), lineWidth: 1)
                        ctx.draw(Text("\(Int(t))°")
                                    .font(.system(size: 9.5)).foregroundColor(Theme.dim),
                                 at: CGPoint(x: xx, y: padT + plotH + 8), anchor: .top)
                    }

                    let sorted = points.sorted { $0.temp < $1.temp }
                    guard sorted.count >= 1 else { return }

                    // 曲线下方填充
                    var fill = Path()
                    fill.move(to: CGPoint(x: px(sorted[0].temp), y: padT + plotH))
                    for p in sorted { fill.addLine(to: CGPoint(x: px(p.temp), y: py(p.duty))) }
                    fill.addLine(to: CGPoint(x: px(sorted[sorted.count - 1].temp), y: padT + plotH))
                    fill.closeSubpath()
                    ctx.fill(fill, with: .linearGradient(
                        Gradient(colors: [Theme.accent.opacity(0.30), Theme.accent.opacity(0.02)]),
                        startPoint: CGPoint(x: 0, y: padT), endPoint: CGPoint(x: 0, y: padT + plotH)))

                    // 曲线
                    var curve = Path()
                    curve.move(to: CGPoint(x: px(sorted[0].temp), y: py(sorted[0].duty)))
                    for p in sorted.dropFirst() { curve.addLine(to: CGPoint(x: px(p.temp), y: py(p.duty))) }
                    ctx.stroke(curve, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                    // 当前温度指示线
                    if let ct = currentTemp, ct >= minTemp, ct <= maxTemp {
                        var v = Path()
                        v.move(to: CGPoint(x: px(ct), y: padT))
                        v.addLine(to: CGPoint(x: px(ct), y: padT + plotH))
                        ctx.stroke(v, with: .color(Theme.orange.opacity(0.75)),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        ctx.draw(Text("\(Int(ct))°")
                                    .font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.orange),
                                 at: CGPoint(x: px(ct), y: padT - 7), anchor: .bottom)
                    }
                }

                // 可拖拽控制点
                ForEach(points.indices, id: \.self) { i in
                    let p = points[i]
                    Circle()
                        .fill(dragIndex == i ? Theme.accent : Theme.panel)
                        .overlay(Circle().stroke(Theme.accent, lineWidth: 2.5))
                        .frame(width: 15, height: 15)
                        .position(x: px(p.temp), y: py(p.duty))
                        .opacity(editable ? 1 : 0.45)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    guard editable else { return }
                                    dragIndex = i
                                    var t = minTemp + Double((v.location.x - padL) / plotW) * (maxTemp - minTemp)
                                    var d = (1.0 - Double((v.location.y - padT) / plotH)) * 100.0
                                    t = min(max(t, minTemp), maxTemp)
                                    d = min(max(d, 0), 100)
                                    let sorted = points.sorted { $0.temp < $1.temp }
                                    if let pos = sorted.firstIndex(where: { $0.id == p.id }) {
                                        let lo = pos > 0 ? sorted[pos - 1].temp + 2 : minTemp
                                        let hi = pos < sorted.count - 1 ? sorted[pos + 1].temp - 2 : maxTemp
                                        t = min(max(t, lo), hi)
                                    }
                                    points[i].temp = (t / 1.0).rounded()
                                    points[i].duty = d.rounded()
                                }
                                .onEnded { _ in dragIndex = nil }
                        )
                }
            }
        }
    }
}

// MARK: - 风扇行

struct FanRow: View {
    let fan: FanState
    let isPump: Bool
    @Binding var selected: Bool
    @Binding var duty: Double
    let manualMode: Bool
    let onDutyChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 勾选
            Button {
                if !isPump { selected.toggle() }
            } label: {
                Image(systemName: isPump ? "lock.fill" : (selected ? "checkmark.square.fill" : "square"))
                    .font(.system(size: 13))
                    .foregroundStyle(isPump ? Theme.orange : (selected ? Theme.accent : Theme.dim))
            }
            .buttonStyle(.plain)
            .disabled(isPump)
            .help(isPump ? L.pumpLockedTip : L.fanSelectTip)

            Text(fan.name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isPump ? Theme.orange : Theme.text)
                .frame(width: 78, alignment: .leading)

            Text("ch\(fan.ch)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.dim)
                .frame(width: 30, alignment: .leading)

            // 转速
            Text(String(format: "%.0f", fan.rpm))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(fan.rpm > 0 ? Theme.text : Theme.dim)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
            Text("RPM").font(.system(size: 9.5)).foregroundStyle(Theme.dim).frame(width: 30, alignment: .leading)

            // 占空比条
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.panel2).frame(width: 90, height: 6)
                Capsule().fill(fan.isManual ? Theme.orange : Theme.accent.opacity(0.7))
                    .frame(width: max(2, 90 * fan.duty / 100.0), height: 6)
            }
            Text(String(format: "%.0f%%", fan.duty))
                .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.dim)
                .monospacedDigit().frame(width: 38, alignment: .trailing)

            Text(fan.modeLabel)
                .font(.system(size: 10.5))
                .foregroundStyle(fan.isManual ? Theme.orange : Theme.dim)
                .frame(width: 74, alignment: .leading)

            Spacer(minLength: 8)

            if isPump {
                Text(L.pumpLockedShort)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.orange)
            } else if manualMode {
                DutySlider(value: Binding(get: { duty }, set: { onDutyChange($0) }),
                           range: 0...100, step: 1, accent: Theme.orange, width: 150)
                Text("\(Int(duty))%")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.text)
                    .monospacedDigit().frame(width: 34, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(isPump ? Theme.orange.opacity(0.06) : Color.clear))
    }
}

// MARK: - 通用格式化

/// 字节 → "1.2 GB"
func fmtBytes(_ v: Double?, decimals: Int = 1) -> String {
    guard let v = v, v.isFinite, v >= 0 else { return "—" }
    let units = ["B", "KB", "MB", "GB", "TB", "PB"]
    var x = v
    var i = 0
    while x >= 1024 && i < units.count - 1 { x /= 1024; i += 1 }
    if i == 0 { return String(format: "%.0f %@", x, units[i]) }
    return String(format: "%.\(decimals)f %@", x, units[i])
}

/// 速率：字节/秒
func fmtRate(_ v: Double?) -> String {
    guard let v = v else { return "—" }
    return fmtBytes(v) + "/s"
}

/// 秒 → "3.4 小时" / "12 分钟"
func fmtUptime(_ s: Double?) -> String {
    guard let s = s, s > 0 else { return "—" }
    if s >= 86400 { return L.days(s / 86400) }
    if s >= 3600  { return L.hours(s / 3600) }
    return L.minutes(s / 60)
}

private func chunked<T>(_ a: [T], _ n: Int) -> [[T]] {
    guard n > 0 else { return [a] }
    return stride(from: 0, to: a.count, by: n).map { Array(a[$0..<min($0 + n, a.count)]) }
}

/// 按占用率着色：0–40 蓝、40–75 橙、>75 红
func loadTint(_ pct: Double) -> Color {
    if pct >= 75 { return Theme.red }
    if pct >= 40 { return Theme.orange }
    return Theme.accent
}

// MARK: - 自绘开关 / 面板开关行 / 页签

/// 自绘小开关（原生 Toggle 在离屏渲染里画不出来，也不够统一）
struct MiniSwitch: View {
    let on: Bool
    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule()
                .fill(on ? Theme.accent : Theme.panel2)
                .overlay(Capsule().stroke(on ? Theme.accent.opacity(0.7) : Theme.stroke, lineWidth: 1))
                .frame(width: 34, height: 19)
            Circle()
                .fill(on ? Color.white : Theme.dim)
                .frame(width: 15, height: 15)
                .padding(.horizontal, 2)
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
        }
        .frame(width: 34, height: 19)
        .animation(.easeOut(duration: 0.12), value: on)
    }
}

/// 开关行：图标 + 名称 + 可选说明 + 自绘开关
/// （参考系统监控类 App 的设置面板。面板开关和菜单栏开关共用。）
struct SwitchRow: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    let on: Bool
    var tint: Color = Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(on ? tint : Theme.dim)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12.5, weight: on ? .medium : .regular))
                        .foregroundStyle(on ? Theme.text : Theme.dim)
                    if let d = detail {
                        Text(d)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.dim.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                MiniSwitch(on: on)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, detail == nil ? 4 : 5)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(on ? tint.opacity(0.08) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(on ? L.hideTip(title) : L.showTip(title))
    }
}

/// 自绘页签（控制 / 监控）
struct PageTab: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11.5))
                Text(title).font(.system(size: 12.5, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? Theme.text : Theme.dim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(selected ? Theme.accent.opacity(0.22) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(selected ? Theme.accent.opacity(0.5) : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 监控面板的公共零件

struct PanelHeader: View {
    let title: String
    var symbol: String? = nil
    var trailing: String? = nil
    var trailingTint: Color = Theme.dim

    var body: some View {
        HStack(spacing: 6) {
            if let s = symbol {
                Image(systemName: s).font(.system(size: 11)).foregroundStyle(Theme.accent)
            }
            SectionTitle(text: title)
            Spacer(minLength: 6)
            if let t = trailing {
                Text(t)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(trailingTint)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }
}

/// 横向进度条（放在 HStack 里撑满剩余空间）
struct FlexBar: View {
    let ratio: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.panel2)
                    .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                Capsule().fill(tint)
                    .frame(width: max(2, geo.size.width * min(max(ratio, 0), 1)))
            }
            .frame(height: geo.size.height)
        }
        .frame(height: height)
    }
}

/// CPU 走势迷你图
struct Sparkline: View {
    let values: [Double]
    var tint: Color = Theme.accent

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let top = max(20.0, values.max() ?? 20)
            var line = Path()
            for (i, v) in values.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
                let y = size.height - size.height * CGFloat(min(max(v, 0), top) / top)
                if i == 0 { line.move(to: CGPoint(x: x, y: y)) }
                else { line.addLine(to: CGPoint(x: x, y: y)) }
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(
                Gradient(colors: [tint.opacity(0.32), tint.opacity(0.02)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(tint),
                       style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }
}

/// 单个核心的小格子
struct CoreCell: View {
    let index: Int
    let pct: Double

    var body: some View {
        let tint = loadTint(pct)
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(Theme.panel2)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(tint.opacity(0.30))
                    .frame(width: max(0, geo.size.width * min(max(pct, 0), 100) / 100))
            }
            HStack(spacing: 2) {
                Text("\(index)")
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundStyle(Theme.dim)
                Spacer(minLength: 0)
                Text(String(format: "%.0f%%", pct))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(pct > 0 ? tint : Theme.dim.opacity(0.7))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 22)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.stroke, lineWidth: 1))
        .help(L.coreTooltip(index, pct))
    }
}

// MARK: - 各监控面板

struct CpuPanel: View {
    let cpu: CpuInfo
    let history: [Double]

    var body: some View {
        Card(padding: 13) {
            VStack(alignment: .leading, spacing: 9) {
                PanelHeader(title: "CPU", symbol: "cpu",
                            trailing: L.threads(cpu.cores))

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f", cpu.total))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(loadTint(cpu.total))
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.dim)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.userPct(cpu.user))
                            .font(.system(size: 10.5, design: .rounded)).foregroundStyle(Theme.dim)
                        Text(L.systemPct(cpu.system))
                            .font(.system(size: 10.5, design: .rounded)).foregroundStyle(Theme.dim)
                    }
                    .monospacedDigit()
                    .padding(.leading, 6)
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(L.labelLoad).font(.system(size: 9.5)).foregroundStyle(Theme.dim)
                        Text(cpu.load.map { String(format: "%.2f", $0) }.joined(separator: " / "))
                            .font(.system(size: 10.5, design: .rounded)).foregroundStyle(Theme.text)
                            .monospacedDigit()
                    }
                }

                Sparkline(values: history, tint: loadTint(cpu.total))
                    .frame(height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L.labelPerCore)
                        .font(.system(size: 9.5)).foregroundStyle(Theme.dim)
                    let cols = 8
                    let rows = chunked(cpu.perCore, cols)
                    // 用 GeometryReader 显式算格子宽度 —— HStack 的 maxWidth: .infinity
                    // 在内容偏宽时会溢出卡片，这里直接给定宽度最稳。
                    GeometryReader { geo in
                        let gap: CGFloat = 3
                        let cellW = max(16, (geo.size.width - CGFloat(cols - 1) * gap) / CGFloat(cols))
                        VStack(alignment: .leading, spacing: gap) {
                            ForEach(rows.indices, id: \.self) { r in
                                HStack(spacing: gap) {
                                    ForEach(rows[r].indices, id: \.self) { c in
                                        CoreCell(index: r * cols + c, pct: rows[r][c])
                                            .frame(width: cellW)
                                    }
                                    if rows[r].count < cols {
                                        ForEach(Array(0..<(cols - rows[r].count)), id: \.self) { _ in
                                            Color.clear.frame(width: cellW, height: 1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: CGFloat(rows.count) * 22 + CGFloat(max(0, rows.count - 1)) * 3)
                }
            }
        }
    }
}

struct MemoryPanel: View {
    let mem: MemInfo

    var body: some View {
        Card(padding: 13) {
            VStack(alignment: .leading, spacing: 9) {
                PanelHeader(title: L.panelMemory, symbol: "memorychip",
                            trailing: "\(fmtBytes(mem.used)) / \(fmtBytes(mem.total))")

                HStack(spacing: 9) {
                    FlexBar(ratio: mem.ratio,
                            tint: mem.ratio > 0.85 ? Theme.red
                                : (mem.ratio > 0.65 ? Theme.orange : Theme.accent),
                            height: 8)
                    Text(String(format: "%.0f%%", mem.ratio * 100))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text).monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }

                HStack(spacing: 14) {
                    memItem(L.labelWired, mem.wired)
                    memItem(L.labelCompressed, mem.compressed)
                    memItem(L.labelSwap, mem.swapUsed, extra: mem.swapTotal > 0 ? "/ \(fmtBytes(mem.swapTotal))" : nil)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func memItem(_ label: String, _ v: Double, extra: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9.5)).foregroundStyle(Theme.dim)
            HStack(spacing: 3) {
                Text(fmtBytes(v))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.text).monospacedDigit()
                if let e = extra {
                    Text(e).font(.system(size: 9.5, design: .rounded)).foregroundStyle(Theme.dim)
                }
            }
        }
    }
}

struct StoragePanel: View {
    let disks: [DiskInfo]

    var body: some View {
        Card(padding: 13) {
            VStack(alignment: .leading, spacing: 9) {
                PanelHeader(title: L.panelStorage, symbol: "internaldrive",
                            trailing: L.volumes(disks.count))

                if disks.isEmpty {
                    Text(L.labelNoVolumes).font(.system(size: 11)).foregroundStyle(Theme.dim)
                } else {
                    VStack(spacing: 7) {
                        ForEach(disks) { d in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(d.name)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 6)
                                    Text("\(fmtBytes(d.used)) / \(fmtBytes(d.total))")
                                        .font(.system(size: 10, design: .rounded))
                                        .foregroundStyle(Theme.dim).monospacedDigit()
                                    Text(String(format: "%.0f%%", d.ratio * 100))
                                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                        .foregroundStyle(d.ratio > 0.9 ? Theme.red
                                                        : (d.ratio > 0.75 ? Theme.orange : Theme.text))
                                        .monospacedDigit()
                                        .frame(width: 34, alignment: .trailing)
                                }
                                FlexBar(ratio: d.ratio,
                                        tint: d.ratio > 0.9 ? Theme.red
                                            : (d.ratio > 0.75 ? Theme.orange : Theme.accent),
                                        height: 5)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct NetworkPanel: View {
    let iface: String
    let down: Double?
    let up: Double?

    var body: some View {
        Card(padding: 13) {
            VStack(alignment: .leading, spacing: 9) {
                PanelHeader(title: L.panelNetwork, symbol: "network", trailing: iface)

                HStack(spacing: 0) {
                    rateBlock("arrow.down", L.labelDown, down, Theme.green)
                    Divider().frame(height: 30).overlay(Theme.stroke)
                    rateBlock("arrow.up", L.labelUp, up, Theme.accent)
                }

                Text(down == nil && up == nil ? L.labelNetSampling : L.labelNetHint)
                    .font(.system(size: 9.5)).foregroundStyle(Theme.dim)
            }
        }
    }

    private func rateBlock(_ symbol: String, _ label: String, _ v: Double?, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 9.5)).foregroundStyle(Theme.dim)
                Text(fmtRate(v))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text).monospacedDigit()
            }
            Spacer(minLength: 8)
        }
    }
}

struct ProcessPanel: View {
    let procs: [ProcInfo]

    var body: some View {
        Card(padding: 13) {
            VStack(alignment: .leading, spacing: 9) {
                PanelHeader(title: L.panelProcesses, symbol: "list.bullet.rectangle",
                            trailing: procs.isEmpty ? nil : L.labelByCPU)

                if procs.isEmpty {
                    Text(L.reading).font(.system(size: 11)).foregroundStyle(Theme.dim)
                } else {
                    let peak = max(1.0, procs.first?.cpu ?? 1)
                    VStack(spacing: 5) {
                        ForEach(procs) { p in
                            HStack(spacing: 8) {
                                Text(p.name)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(width: 148, alignment: .leading)
                                FlexBar(ratio: p.cpu / peak, tint: loadTint(p.cpu), height: 5)
                                Text(String(format: "%.1f%%", p.cpu))
                                    .font(.system(size: 10.5, design: .rounded))
                                    .foregroundStyle(Theme.dim).monospacedDigit()
                                    .frame(width: 44, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct SensorPanel: View {
    let items: [SensorItem]

    var body: some View {
        Card(padding: 13) {
            VStack(alignment: .leading, spacing: 9) {
                PanelHeader(title: L.panelSensors, symbol: "thermometer.medium",
                            trailing: L.labelFromSMC)

                if items.isEmpty {
                    Text(L.labelNoSensors).font(.system(size: 11)).foregroundStyle(Theme.dim)
                } else {
                    VStack(spacing: 4) {
                        ForEach(Array(chunked(items, 4).enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 4) {
                                ForEach(row) { it in
                                    VStack(spacing: 1) {
                                        Text(it.label)
                                            .font(.system(size: 9))
                                            .foregroundStyle(Theme.dim)
                                            .lineLimit(1)
                                        Text(String(format: "%.0f°", it.value))
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(tempTint(it.value))
                                            .monospacedDigit()
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel2))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.stroke, lineWidth: 1))
                                }
                                // 补齐最后一行，避免格子被拉伸
                                if row.count < 4 {
                                    ForEach(Array(0..<(4 - row.count)), id: \.self) { _ in
                                        Color.clear.frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct SystemPanel: View {
    let cpu: CpuInfo
    let version: String

    var body: some View {
        Card(padding: 13) {
            VStack(alignment: .leading, spacing: 8) {
                PanelHeader(title: L.panelSystem, symbol: "info.circle", trailing: "v\(version)")

                Text(cpu.brand.isEmpty ? L.labelUnknownCPU : cpu.brand)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 16) {
                    kv(L.labelLogicalCores, "\(cpu.cores)")
                    kv(L.labelUptime, fmtUptime(cpu.uptime))
                    kv(L.labelLoad, String(format: "%.2f", cpu.load.first ?? 0))
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.system(size: 9.5)).foregroundStyle(Theme.dim)
            Text(v).font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.text).monospacedDigit()
        }
    }
}

/// 显卡面板（只读监控）。显卡风扇由显卡固件管理，本程序不参与调速。
struct GpuPanel: View {
    let g: GpuState

    var body: some View {
        Card(padding: 13) {
            VStack(alignment: .leading, spacing: 9) {
                PanelHeader(title: L.panelGPU, symbol: "display", trailing: L.labelReadOnlyMonitor)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        MetricChip(symbol: "fanblades.fill", label: L.labelGPUFan,
                                   value: fmt0(g.fanRPM),
                                   sub: g.fanRPM == nil ? nil
                                        : (g.fanPercent.map { String(format: "RPM · %.0f%%", $0) } ?? "RPM"),
                                   tint: Theme.text)
                        MetricChip(symbol: "thermometer.medium", label: L.labelTemp,
                                   value: fmt0(g.temp),
                                   sub: g.temp == nil ? nil : "°C",
                                   tint: tempTint(g.temp))
                        MetricChip(symbol: "bolt.fill", label: L.labelPower,
                                   value: fmt0(g.power),
                                   sub: g.power == nil ? nil : "W",
                                   tint: Theme.text)
                    }
                    HStack(spacing: 8) {
                        MetricChip(symbol: "speedometer", label: L.labelCoreClock,
                                   value: fmt0(g.coreClock),
                                   sub: g.coreClock == nil ? nil : "MHz",
                                   tint: Theme.text)
                        MetricChip(symbol: "memorychip", label: L.labelMemClock,
                                   value: fmt0(g.memClock),
                                   sub: g.memClock == nil ? nil : "MHz",
                                   tint: Theme.text)
                        MetricChip(symbol: "gauge.with.dots.needle.bottom.50percent", label: L.labelUtilization,
                                   value: g.utilization.map { String(format: "%.0f", $0) } ?? "—",
                                   sub: g.utilization == nil ? nil : "%",
                                   tint: Theme.text)
                    }
                }

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10)).foregroundStyle(Theme.dim)
                    Text(L.gpuNote)
                        .font(.system(size: 10)).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - 监控页（可单独开关的面板）

/// 两列排布所有已开启的面板。**不含 ScrollView** —— 外层在 App 里再包一层，
/// 这样离屏渲染可以直接渲染这个视图。
struct MonitorPanels: View {
    @ObservedObject var ctl: FanController

    var body: some View {
        if ctl.sys == nil {
            Card(padding: 20) {
                HStack(spacing: 10) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 13)).foregroundStyle(Theme.dim)
                    Text(L.headerReading)
                        .font(.system(size: 12)).foregroundStyle(Theme.dim)
                    Spacer()
                }
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 14) {
                    if ctl.panel(.cpu), let c = ctl.cpuInfo {
                        CpuPanel(cpu: c, history: ctl.cpuHistory)
                    }
                    if ctl.panel(.memory), let m = ctl.memInfo {
                        MemoryPanel(mem: m)
                    }
                    if ctl.panel(.network), let n = ctl.sys?.net {
                        NetworkPanel(iface: n.iface, down: ctl.netDown, up: ctl.netUp)
                    }
                    if ctl.panel(.sensors) {
                        SensorPanel(items: ctl.sensorItems)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)

                VStack(spacing: 14) {
                    if ctl.panel(.gpu), let g = ctl.gpu {
                        GpuPanel(g: g)
                    }
                    if ctl.panel(.processes) {
                        ProcessPanel(procs: ctl.procs)
                    }
                    if ctl.panel(.storage) {
                        StoragePanel(disks: ctl.disks)
                    }
                    if ctl.panel(.system), let c = ctl.cpuInfo {
                        SystemPanel(cpu: c, version: FanController.version)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
}

// MARK: - 菜单栏（状态栏）

/// 菜单栏上每一项显示的文字。nil = 只显示图标
func menuBarText(_ ctl: FanController, _ k: MenuBarItem) -> String? {
    switch k {
    case .icon:    return nil
    case .cpuTemp: return ctl.cpuTemp.map { String(format: "%.0f°", $0) }
    case .gpuTemp: return ctl.gpuTemp.map { String(format: "%.0f°", $0) }
    case .cpuLoad: return ctl.cpuInfo.map { String(format: "%.0f%%", $0.total) }
    case .memory:  return ctl.memInfo.map { String(format: "%.0f%%", $0.ratio * 100) }
    case .fanRPM:  return ctl.topFanRPM.map { String(format: "%.0f", $0) }
    case .gpuFan:  return ctl.gpuFanRPM.map { String(format: "%.0f", $0) }
    case .network: return ctl.netDown.map { compactRate($0) }
    }
}

/// 速率紧凑写法：1.2M / 240K / 0（菜单栏上空间紧张，不写 /s）
func compactRate(_ v: Double) -> String {
    if v >= 1048576 { return String(format: "%.1fM", v / 1048576) }
    if v >= 1024    { return String(format: "%.0fK", v / 1024) }
    return String(format: "%.0f", v)
}

/// 菜单栏上真正显示的内容由 AppKit 侧的 `StatusItemController.render()` 负责
/// （SwiftUI 的 MenuBarExtra 只支持「一个图标 + 一段文字」，做不了多项，详见 StatusItem.swift）。
/// 这里只回答「每一项该显示什么文字」，两侧共用。nil = 只显示图标。
struct MenuBarPanel: View {
    @ObservedObject var ctl: FanController
    /// 由 StatusItemController 注入：打开主窗口 + 收起面板。
    /// 默认空实现是为了离屏渲染（render.swift 不编译 StatusItem.swift）。
    var openMain: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            VStack(alignment: .leading, spacing: 10) {
                liveStats
                Divider().overlay(Theme.stroke)
                menuBarToggles
                Divider().overlay(Theme.stroke)
                launchAtLoginRow
            }
            .padding(12)
            Divider().overlay(Theme.stroke)
            actions
        }
        .frame(width: 326)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }

    private var statusTint: Color {
        switch ctl.statusColor {
        case .green:  return Theme.green
        case .orange: return Theme.orange
        case .grey:   return Theme.dim
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "fanblades.fill")
                .font(.system(size: 14)).foregroundStyle(Theme.accent)
            Text(L.appName)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            Spacer(minLength: 6)
            HStack(spacing: 5) {
                Circle().fill(statusTint).frame(width: 6, height: 6)
                Text(ctl.statusText).font(.system(size: 10.5)).foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var liveStats: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                stat("cpu", "CPU", ctl.cpuTemp.map { String(format: "%.0f°C", $0) } ?? "—",
                     tempTint(ctl.cpuTemp))
                stat("display", "GPU", ctl.gpuTemp.map { String(format: "%.0f°C", $0) } ?? "—",
                     tempTint(ctl.gpuTemp))
            }
            HStack(spacing: 6) {
                stat("speedometer", L.statLoad, ctl.cpuInfo.map { String(format: "%.0f%%", $0.total) } ?? "—",
                     ctl.cpuInfo.map { loadTint($0.total) } ?? Theme.dim)
                stat("memorychip", L.statMemory, ctl.memInfo.map { String(format: "%.0f%%", $0.ratio * 100) } ?? "—",
                     Theme.text)
            }
            HStack(spacing: 6) {
                stat("wind", L.statFan, ctl.topFanRPM.map { String(format: "%.0f", $0) } ?? "—", Theme.text)
                stat("fanblades", L.statGPU, ctl.gpuFanRPM.map { String(format: "%.0f", $0) } ?? "—", Theme.text)
            }
            HStack(spacing: 6) {
                stat("arrow.down", L.labelDown, fmtRate(ctl.netDown), Theme.green)
                stat("arrow.up", L.labelUp, fmtRate(ctl.netUp), Theme.accent)
            }
        }
    }

    private func stat(_ symbol: String, _ label: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10)).foregroundStyle(Theme.dim).frame(width: 13)
            Text(label).font(.system(size: 10.5)).foregroundStyle(Theme.dim)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(tint).monospacedDigit()
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.panel2))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.stroke, lineWidth: 1))
    }

    private var menuBarToggles: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                SectionTitle(text: L.menuBarSection)
                Spacer()
                Text("\(ctl.menuBarItems.count) / \(MenuBarItem.allCases.count)")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Theme.dim).monospacedDigit()
            }
            VStack(spacing: 1) {
                ForEach(MenuBarItem.allCases) { k in
                    SwitchRow(symbol: k.symbol, title: k.label, on: ctl.menuBar(k)) {
                        ctl.toggleMenuBar(k)
                    }
                }
            }
            Text(L.menuBarEmptyHint)
                .font(.system(size: 9.5)).foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 开机自启。用 SMAppService 注册为登录项，系统设置里能看到、也能自己关。
    private var launchAtLoginRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            SwitchRow(symbol: "power", title: L.launchAtLogin, on: ctl.launchAtLogin) {
                ctl.setLaunchAtLogin(!ctl.launchAtLogin)
            }
            Text(L.launchAtLoginHint)
                .font(.system(size: 9.5)).foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                openMain()
            } label: {
                Text(L.openMainWindow)
                    .font(.system(size: 11.5))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button { ctl.refresh() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .help(L.refreshTip)

            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .help(L.quitTip)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }
}

// MARK: - 主界面

struct ContentView: View {
    @ObservedObject var ctl: FanController
    @State private var showHelp = false
    /// 0 = 控制，1 = 监控
    @State private var page: Int
    /// 监控页是否套一层滚动。离屏渲染画不出 ScrollView，预览时置 false。
    private let scrollMonitor: Bool

    /// startPage / scrollMonitor 只给离屏渲染用，正常打开始终从控制页开始
    init(ctl: FanController, startPage: Int = 0, scrollMonitor: Bool = true) {
        self.ctl = ctl
        self.scrollMonitor = scrollMonitor
        _page = State(initialValue: startPage)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            HStack(alignment: .top, spacing: 14) {
                sidebar.frame(width: 300)
                main.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(14)
            Divider().overlay(Theme.stroke)
            footer
        }
        .frame(minWidth: 1040, minHeight: 830)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }

    // 顶栏
    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "fanblades.fill")
                .font(.system(size: 19))
                .foregroundStyle(Theme.accent)
            Text(L.appName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)

            statusPill

            Spacer()

            TempChip(label: "CPU", value: ctl.cpuTemp, tint: tempTint(ctl.cpuTemp))
            TempChip(label: "GPU", value: ctl.gpuTemp, tint: tempTint(ctl.gpuTemp),
                     extra: ctl.gpuFanRPM.map { String(format: "· %.0f RPM", $0) })

            Button {
                ctl.returnToBIOS()
            } label: {
                Label(L.headerReturnBIOS, systemImage: "arrow.uturn.backward")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)

            Button {
                showHelp.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 13))
            }
            .buttonStyle(.bordered)
            .help(L.headerHelpTip)
            .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                helpCard.frame(width: 430)
            }

            Button {
                ctl.apply()
            } label: {
                Label(ctl.busy ? L.headerApplying : L.headerApply, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(ctl.busy || ctl.snapshot == nil)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var statusPill: some View {
        let (color, text): (Color, String) = {
            switch ctl.statusColor {
            case .green: return (Theme.green, ctl.statusText)
            case .orange: return (Theme.orange, ctl.statusText)
            case .grey: return (Theme.dim, ctl.statusText)
            }
        }()
        return HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(Capsule().fill(Theme.panel2))
    }

    // 左栏（随页签切换内容）
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card(padding: 6) {
                HStack(spacing: 4) {
                    PageTab(title: L.tabControl, symbol: "slider.horizontal.3", selected: page == 0) { page = 0 }
                    PageTab(title: L.tabMonitor, symbol: "chart.bar.fill", selected: page == 1) { page = 1 }
                }
            }

            if page == 0 { controlSidebar } else { panelSidebar }

            Spacer(minLength: 0)
        }
    }

    /// 控制页侧栏：模式 + 温度来源
    private var controlSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(text: L.controlModeSection)
                    ForEach(ControlMode.allCases) { m in
                        ModeRow(mode: m,
                                selected: ctl.mode == m,
                                applied: ctl.appliedMode == m && (ctl.snapshot?.service.running ?? false)) {
                            ctl.mode = m
                            ctl.minDuty = m.minDuty
                        }
                    }
                }
            }

            Card(padding: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: L.tempSourceSection)
                    sensorRow(title: "CPU", on: $ctl.useCPU, choice: $ctl.cpuChoice,
                              choices: SensorChoice.cpuChoices, temp: ctl.cpuTemp, tint: tempTint(ctl.cpuTemp))
                    Divider().overlay(Theme.stroke)
                    sensorRow(title: "GPU", on: $ctl.useGPU, choice: $ctl.gpuChoice,
                              choices: SensorChoice.gpuChoices, temp: ctl.gpuTemp, tint: tempTint(ctl.gpuTemp))
                    Text(L.tempSourceHint)
                        .font(.system(size: 10)).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 监控页侧栏：面板显示开关
    private var panelSidebar: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionTitle(text: L.panelSection)
                    Spacer()
                    Text("\(ctl.enabledPanels.count) / \(PanelKind.allCases.count)")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Theme.dim).monospacedDigit()
                }

                VStack(spacing: 2) {
                    ForEach(PanelKind.allCases) { k in
                        SwitchRow(symbol: k.symbol, title: k.label, detail: k.detail,
                                  on: ctl.panel(k)) { ctl.togglePanel(k) }
                    }
                }

                Divider().overlay(Theme.stroke)

                HStack(spacing: 6) {
                    Button {
                        ctl.enabledPanels = Set(PanelKind.allCases)
                    } label: {
                        Text(L.showAll).font(.system(size: 11)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        ctl.enabledPanels = []
                    } label: {
                        Text(L.hideAll).font(.system(size: 11)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Text(L.panelSectionHint)
                    .font(.system(size: 10)).foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 一个温度来源：勾选 + 来源二选一（自绘分段按钮，不用 Picker）
    private func sensorRow(title: String, on: Binding<Bool>, choice: Binding<SensorChoice>,
                           choices: [SensorChoice], temp: Double?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(isOn: on) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                    Text(temp.map { String(format: "%.0f°C", $0) } ?? "—")
                        .font(.system(size: 11, design: .rounded)).foregroundStyle(tint)
                        .monospacedDigit()
                }
            }
            .toggleStyle(.checkbox)

            HStack(spacing: 6) {
                ForEach(choices) { c in
                    let sel = choice.wrappedValue == c
                    Button { choice.wrappedValue = c } label: {
                        Text(c.short)
                            .font(.system(size: 11))
                            .foregroundStyle(sel ? Theme.text : Theme.dim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(sel ? Theme.accent.opacity(0.22) : Theme.panel2))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(sel ? Theme.accent.opacity(0.55) : Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(c.label)
                }
            }
            .opacity(on.wrappedValue ? 1 : 0.4)
        }
    }

    // 右栏
    private var main: some View {
        Group {
            if page == 0 { controlPage } else { monitorPage }
        }
    }

    /// 监控页：面板较多，这里给一层滚动；面板本体在 MonitorPanels 里
    private var monitorPage: some View {
        Group {
            if scrollMonitor {
                ScrollView(.vertical, showsIndicators: false) {
                    MonitorPanels(ctl: ctl).padding(.trailing, 4)
                }
            } else {
                MonitorPanels(ctl: ctl)
            }
        }
    }

    /// 控制页：曲线 + 风扇通道（显卡监控已挪到监控页）
    private var controlPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionTitle(text: ctl.mode == .manual ? L.manualDutySection : L.dutyCurveSection)
                        Spacer()
                        if ctl.mode.usesCurve {
                            Text(ctl.mode == .custom ? L.curveEditableHint : L.curvePresetHint)
                                .font(.system(size: 10)).foregroundStyle(Theme.dim)
                        }
                    }
                    if ctl.mode.usesCurve {
                        CurveEditor(points: ctl.mode == .custom ? $ctl.customPoints : .constant(ctl.activeCurve()),
                                    editable: ctl.mode == .custom,
                                    currentTemp: ctl.useCPU ? ctl.cpuTemp : ctl.gpuTemp)
                            .frame(height: 175)

                        // 最低占空比：曲线之外的下限，风扇不会低于这个值（全速模式无意义，隐藏）
                        if ctl.mode != .full {
                            HStack(spacing: 10) {
                            Text(L.minDuty)
                                .font(.system(size: 11.5)).foregroundStyle(Theme.dim)
                                .frame(width: 66, alignment: .leading)
                            DutySlider(value: $ctl.minDuty, range: 0...60, step: 1,
                                       accent: ctl.minDuty < 15 ? Theme.orange : Theme.accent,
                                       width: 240)
                            Text("\(Int(ctl.minDuty.rounded()))%")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundStyle(ctl.minDuty < 15 ? Theme.orange : Theme.text)
                                .monospacedDigit()
                                .frame(width: 40, alignment: .leading)
                            if ctl.minDuty < 15 {
                                Text(L.minDutyWarn)
                                    .font(.system(size: 10.5)).foregroundStyle(Theme.orange)
                            } else {
                                Text(L.minDutyHint)
                                    .font(.system(size: 10.5)).foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            }
                        }

                        if ctl.mode == .custom {
                            HStack(spacing: 10) {
                                Button {
                                    let sorted = ctl.customPoints.sorted { $0.temp < $1.temp }
                                    var t = 60.0
                                    if sorted.count >= 2 {
                                        var best = 0.0
                                        for i in 0..<(sorted.count - 1) {
                                            let gap = sorted[i + 1].temp - sorted[i].temp
                                            if gap > best { best = gap; t = (sorted[i].temp + sorted[i + 1].temp) / 2 }
                                        }
                                    }
                                    ctl.customPoints.append(.init(temp: t.rounded(), duty: 70))
                                } label: { Label(L.addPoint, systemImage: "plus") .font(.system(size: 11)) }
                                .buttonStyle(.bordered)

                                Button {
                                    if ctl.customPoints.count > 2 {
                                        let sorted = ctl.customPoints.sorted { $0.temp < $1.temp }
                                        let mid = sorted[sorted.count / 2]
                                        ctl.customPoints.removeAll { $0.id == mid.id }
                                    }
                                } label: { Label(L.removePoint, systemImage: "minus").font(.system(size: 11)) }
                                .buttonStyle(.bordered)

                                Text(ctl.activeCurve().sorted { $0.temp < $1.temp }
                                        .map { String(format: "%.0f°→%.0f%%", $0.temp, $0.duty) }
                                        .joined(separator: "   "))
                                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.dim)
                            }
                        }
                    } else {
                        Text(L.manualHint)
                            .font(.system(size: 12)).foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    }
                }
            }

            Card(padding: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        SectionTitle(text: L.fanChannelSection)
                        Spacer()
                        Text(L.fanChannelHint)
                            .font(.system(size: 10)).foregroundStyle(Theme.dim)
                    }
                    .padding(.bottom, 4)
                    if ctl.pumpUnconfirmed {
                        HStack(spacing: 7) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10.5)).foregroundStyle(Theme.orange)
                            Text(L.pumpUnconfirmed(ctl.snapshot?.pumpChannel ?? 6))
                                .font(.system(size: 10.5)).foregroundStyle(Theme.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.orange.opacity(0.12)))
                        .padding(.bottom, 6)
                    }
                    ForEach(ctl.snapshot?.fans ?? []) { f in
                        let isPump = f.ch == (ctl.snapshot?.pumpChannel ?? -1)
                        FanRow(fan: f,
                               isPump: isPump,
                               selected: Binding(
                                    get: { ctl.selectedFans.contains(f.ch) },
                                    set: { v in
                                        if v { ctl.selectedFans.insert(f.ch) }
                                        else { ctl.selectedFans.remove(f.ch) }
                                    }),
                               duty: Binding(
                                    get: { ctl.manualDuty[f.ch] ?? 40 },
                                    set: { ctl.manualDuty[f.ch] = $0 }),
                               manualMode: ctl.mode == .manual && !isPump,
                               onDutyChange: { ctl.setDutyLive(ch: f.ch, duty: $0) })
                    }
                }
            }

            overviewStrip

            Spacer(minLength: 0)
        }
    }

    /// 控制页底部的一条概览 —— 顺手把监控页的数据带一眼，也把空白填上
    private var overviewStrip: some View {
        Card(padding: 12) {
            HStack(spacing: 16) {
                SectionTitle(text: L.overviewSection)
                if let c = ctl.cpuInfo {
                    overviewItem("cpu", "CPU", String(format: "%.0f%%", c.total), loadTint(c.total))
                }
                if let m = ctl.memInfo {
                    overviewItem("memorychip", L.statMemory, String(format: "%.0f%%", m.ratio * 100),
                                 m.ratio > 0.85 ? Theme.red : Theme.accent)
                }
                if let d = ctl.disks.first {
                    overviewItem("internaldrive", L.systemDisk, String(format: "%.0f%%", d.ratio * 100),
                                 d.ratio > 0.9 ? Theme.red : Theme.accent)
                }
                overviewItem("arrow.down", L.labelDown, fmtRate(ctl.netDown), Theme.green)
                overviewItem("arrow.up", L.labelUp, fmtRate(ctl.netUp), Theme.accent)
                Spacer(minLength: 8)
                Text(L.overviewMore)
                    .font(.system(size: 10)).foregroundStyle(Theme.dim)
            }
        }
    }

    private func overviewItem(_ symbol: String, _ label: String,
                              _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Theme.dim)
            Text(label).font(.system(size: 10.5)).foregroundStyle(Theme.dim)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(tint).monospacedDigit()
        }
    }

    /// 说明卡：放在标题栏的 ? 弹出面板里，不占用主布局高度
    var helpCard: some View {
        let svc = ctl.snapshot?.service
        let svcText: String = {
            guard let svc = svc else { return L.svcUnknown }
            if !svc.installed { return L.svcNotInstalled }
            return svc.running ? L.svcRunning : L.svcInstalledNotRunning
        }()
        return Card(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionTitle(text: L.helpTitle)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(svc?.running == true ? Theme.green : Theme.dim)
                            .frame(width: 6, height: 6)
                        Text(L.backgroundService(svcText))
                            .font(.system(size: 10.5)).foregroundStyle(Theme.dim)
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    helpLine("checkmark.circle.fill", Theme.accent,
                             L.helpControl1)
                    helpLine("arrow.uturn.backward", Theme.dim,
                             L.helpControl2)
                    helpLine("slider.horizontal.3", Theme.dim,
                             L.helpControl3)
                    helpLine("exclamationmark.triangle.fill", Theme.orange,
                             L.helpPump(ctl.snapshot?.pumpChannel ?? 6))
                    helpLine("fanblades", Theme.dim,
                             L.helpMonitor)
                    helpLine("display", Theme.dim,
                             L.helpGPU)
                    helpLine("cpu", Theme.dim,
                             L.helpReadOnly)
                    helpLine("lock.shield", Theme.dim,
                             L.helpSudo)
                }
            }
        }
    }

    private func helpLine(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10.5)).foregroundStyle(tint)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 11.5)).foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if ctl.needsInstall {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.orange)
            }
            Text(ctl.message.isEmpty ? L.ready : ctl.message)
                .font(.system(size: 11))
                .foregroundStyle(ctl.needsInstall ? Theme.orange : Theme.dim)
                .lineLimit(2)
            Spacer()
            Text(L.footerHint)
                .font(.system(size: 10)).foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }
}
