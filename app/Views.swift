import SwiftUI

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
                            Text("运行中")
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
            .help(isPump ? "水泵通道，已锁定不参与调速" : "是否参与调速")

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
                Text("水泵 · 已锁定")
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

// MARK: - 显卡监控卡片（只读）

/// 显卡监控。显卡风扇由显卡固件的 PowerPlay 表与驱动共同管理，
/// macOS 没有对外开放的写入接口 —— 所以这里只读、不参与调速。
struct GpuCard: View {
    let g: GpuState

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(text: "显卡")
                    Spacer()
                    Text("只读监控 · 不参与调速")
                        .font(.system(size: 10)).foregroundStyle(Theme.dim)
                }

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        MetricChip(symbol: "fanblades.fill", label: "风扇",
                                   value: fmt0(g.fanRPM),
                                   sub: g.fanRPM == nil ? nil
                                        : (g.fanPercent.map { String(format: "RPM · %.0f%%", $0) } ?? "RPM"),
                                   tint: Theme.text)
                        MetricChip(symbol: "thermometer.medium", label: "温度",
                                   value: fmt0(g.temp),
                                   sub: g.temp == nil ? nil : "°C",
                                   tint: tempTint(g.temp))
                        MetricChip(symbol: "bolt.fill", label: "功耗",
                                   value: fmt0(g.power),
                                   sub: g.power == nil ? nil : "W",
                                   tint: Theme.text)
                    }
                    HStack(spacing: 8) {
                        MetricChip(symbol: "speedometer", label: "核心频率",
                                   value: fmt0(g.coreClock),
                                   sub: g.coreClock == nil ? nil : "MHz",
                                   tint: Theme.text)
                        MetricChip(symbol: "memorychip", label: "显存频率",
                                   value: fmt0(g.memClock),
                                   sub: g.memClock == nil ? nil : "MHz",
                                   tint: Theme.text)
                        MetricChip(symbol: "gauge.with.dots.needle.bottom.50percent", label: "占用率",
                                   value: g.utilization.map { String(format: "%.0f", $0) } ?? "—",
                                   sub: g.utilization == nil ? nil : "%",
                                   tint: Theme.text)
                    }
                }

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10)).foregroundStyle(Theme.dim)
                    Text("显卡风扇由显卡固件的 PowerPlay 表与驱动管理，macOS 没有开放的写入接口 —— "
                         + "所以显卡风扇只能看、不能调。要改它得在 OpenCore 里注入修改过的风扇曲线，重启生效。")
                        .font(.system(size: 10)).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - 主界面

struct ContentView: View {
    @ObservedObject var ctl: FanController
    @State private var showHelp = false

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
            Text("风扇控制")
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
                Label("交还 BIOS", systemImage: "arrow.uturn.backward")
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
            .help("使用说明")
            .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                helpCard.frame(width: 430)
            }

            Button {
                ctl.apply()
            } label: {
                Label(ctl.busy ? "应用中…" : "应用", systemImage: "checkmark.circle.fill")
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

    // 左栏：控制模式 + 温度来源
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(text: "控制模式")
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
                    SectionTitle(text: "温度来源")
                    sensorRow(title: "CPU", on: $ctl.useCPU, choice: $ctl.cpuChoice,
                              choices: SensorChoice.cpuChoices, temp: ctl.cpuTemp, tint: tempTint(ctl.cpuTemp))
                    Divider().overlay(Theme.stroke)
                    sensorRow(title: "GPU", on: $ctl.useGPU, choice: $ctl.gpuChoice,
                              choices: SensorChoice.gpuChoices, temp: ctl.gpuTemp, tint: tempTint(ctl.gpuTemp))
                    Text("同时勾选时，取两者中较热的那个；每条来源内部也取最热")
                        .font(.system(size: 10)).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
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

    // 右栏：曲线 + 风扇通道 + 显卡
    private var main: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionTitle(text: ctl.mode == .manual ? "手动占空比" : "温度 → 占空比 曲线")
                        Spacer()
                        if ctl.mode.usesCurve {
                            Text(ctl.mode == .custom ? "拖动圆点调整，下方按钮增删" : "预设曲线（切换到自定义可编辑）")
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
                            Text("最低占空比")
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
                                Text("过低时部分风扇可能停转，留意下面转速")
                                    .font(.system(size: 10.5)).foregroundStyle(Theme.orange)
                            } else {
                                Text("曲线端点之外，占空比不会低于此值")
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
                                } label: { Label("添加控制点", systemImage: "plus") .font(.system(size: 11)) }
                                .buttonStyle(.bordered)

                                Button {
                                    if ctl.customPoints.count > 2 {
                                        let sorted = ctl.customPoints.sorted { $0.temp < $1.temp }
                                        let mid = sorted[sorted.count / 2]
                                        ctl.customPoints.removeAll { $0.id == mid.id }
                                    }
                                } label: { Label("删除控制点", systemImage: "minus").font(.system(size: 11)) }
                                .buttonStyle(.bordered)

                                Text(ctl.activeCurve().sorted { $0.temp < $1.temp }
                                        .map { String(format: "%.0f°→%.0f%%", $0.temp, $0.duty) }
                                        .joined(separator: "   "))
                                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.dim)
                            }
                        }
                    } else {
                        Text("手动模式下，下面每个风扇的滑块直接设定固定占空比；不会跟随温度变化。")
                            .font(.system(size: 12)).foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    }
                }
            }

            Card(padding: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        SectionTitle(text: "风扇通道")
                        Spacer()
                        Text("水泵通道已锁定 · 每 2 秒刷新")
                            .font(.system(size: 10)).foregroundStyle(Theme.dim)
                    }
                    .padding(.bottom, 4)
                    if ctl.pumpUnconfirmed {
                        HStack(spacing: 7) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10.5)).foregroundStyle(Theme.orange)
                            Text("水泵通道用的是默认值 ch\(ctl.snapshot?.pumpChannel ?? 6)，未从配置读到 —— 换过机器请核对后再调速，"
                                 + "确认办法见「?」里的说明。")
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

            if let g = ctl.gpu {
                GpuCard(g: g)
            }

            Spacer(minLength: 0)
        }
    }

    /// 说明卡：放在标题栏的 ? 弹出面板里，不占用主布局高度
    var helpCard: some View {
        let svc = ctl.snapshot?.service
        let svcText: String = {
            guard let svc = svc else { return "未知" }
            if !svc.installed { return "未安装" }
            return svc.running ? "运行中" : "已安装 · 未运行"
        }()
        return Card(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionTitle(text: "说明")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(svc?.running == true ? Theme.green : Theme.dim)
                            .frame(width: 6, height: 6)
                        Text("后台服务 \(svcText)")
                            .font(.system(size: 10.5)).foregroundStyle(Theme.dim)
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    helpLine("checkmark.circle.fill", Theme.accent,
                             "「应用」把当前模式写入后台服务 gpufand，之后即使关掉本窗口也持续生效。")
                    helpLine("arrow.uturn.backward", Theme.dim,
                             "「交还 BIOS」停止后台服务，所有风扇交回主板 SmartFan 曲线。")
                    helpLine("slider.horizontal.3", Theme.dim,
                             "手动模式会先停掉后台服务，再用每个风扇的滑块直接设定固定占空比。")
                    helpLine("exclamationmark.triangle.fill", Theme.orange,
                             "水冷泵（ch\(ctl.snapshot?.pumpChannel ?? 6)）被锁定，不参与调速 —— 泵速过低会导致冷液流量不足。"
                             + "通道号记在 /usr/local/etc/fancontrol.conf 的 pump_channel。")
                    helpLine("display", Theme.dim,
                             "「显卡」卡片是只读的：显卡风扇由显卡固件的 PowerPlay 表与驱动管理，"
                             + "macOS 没有开放写入接口，本程序不参与显卡调速。无驱动的显卡"
                             + "（如 macOS 下的 NVIDIA 30 系）不会出现这张卡片。")
                    helpLine("lock.shield", Theme.dim,
                             "写 SMC 需要特权，安装脚本已为 fanctl 配置免密规则；撤销见 install.sh 末尾。")
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
            Text(ctl.message.isEmpty ? "就绪" : ctl.message)
                .font(.system(size: 11))
                .foregroundStyle(ctl.needsInstall ? Theme.orange : Theme.dim)
                .lineLimit(2)
            Spacer()
            Text("曲线由 gpufand 后台服务执行 · 重启后自动恢复")
                .font(.system(size: 10)).foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
    }
}
