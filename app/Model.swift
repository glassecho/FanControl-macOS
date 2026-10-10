import Foundation
import Combine

// MARK: - 来自辅助程序的状态

struct FanState: Decodable, Identifiable {
    let ch: Int
    let name: String
    let rpm: Double
    let pwm: Double
    let duty: Double
    let mode: Double
    let target: Double
    let min: Double
    let max: Double
    let controllable: Bool
    var id: Int { ch }

    /// 0 = BIOS 智能调速, 1 = 按转速闭环, 2 = 按占空比
    var modeLabel: String {
        switch Int(mode) {
        case 1: return "手动·转速"
        case 2: return "手动·占空比"
        default: return "BIOS"
        }
    }
    var isManual: Bool { Int(mode) != 0 }
}

struct SensorState: Decodable, Identifiable {
    let key: String
    let value: Double
    var id: String { key }
}

struct ServiceState: Decodable {
    let installed: Bool
    let running: Bool
    let conf: Bool
}

/// 显卡监控数据。显卡风扇由显卡固件管理，本程序只读、不参与调速。
/// 所有字段都是可选的 —— 不同显卡暴露的字段不同，无驱动的卡整个 gpu 都缺失。
struct GpuState: Decodable {
    let fanRPM: Double?
    let fanPercent: Double?
    let temp: Double?
    let power: Double?
    let coreClock: Double?
    let memClock: Double?
    let utilization: Double?
}

struct Snapshot: Decodable {
    let ok: Bool
    let pumpChannel: Int
    /// false/缺失 = 水泵通道用的是内置默认值（换机器后应当确认）
    let pumpConfigured: Bool?
    let fans: [FanState]
    let sensors: [SensorState]
    let service: ServiceState
    /// 只读的显卡监控；无驱动的显卡（如 macOS 下的 NVIDIA 30 系）不会有这个字段
    let gpu: GpuState?

    func sensor(_ key: String) -> Double? {
        sensors.first { $0.key == key }?.value
    }
}

// MARK: - 曲线

struct CurvePoint: Identifiable, Equatable {
    var id = UUID()
    var temp: Double
    var duty: Double
}

enum ControlMode: String, CaseIterable, Identifiable {
    case silent, standard, performance, full, manual, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .silent:      return "安静"
        case .standard:    return "标准"
        case .performance: return "性能"
        case .full:        return "全速"
        case .manual:      return "手动"
        case .custom:      return "自定义曲线"
        }
    }

    var detail: String {
        switch self {
        case .silent:      return "最低 10%，85°C 才拉满"
        case .standard:    return "平衡，日常默认"
        case .performance: return "提前提速，压制温度"
        case .full:        return "固定 100% 占空比"
        case .manual:      return "每个风扇一个固定占空比"
        case .custom:      return "自己拖动曲线控制点"
        }
    }

    var symbol: String {
        switch self {
        case .silent:      return "moon.zzz.fill"
        case .standard:    return "dial.medium.fill"
        case .performance: return "bolt.fill"
        case .full:        return "wind"
        case .manual:      return "slider.horizontal.3"
        case .custom:      return "point.topleft.down.to.point.bottomright.curvepath"
        }
    }

    /// nil = 手动模式（不用温度曲线守护进程）
    /// 曲线按「CPU 核心」传感器的量程设计：空闲 ~30°C，满载 85–95°C
    var curve: [CurvePoint]? {
        switch self {
        case .silent:
            // 最低 10%，到 85°C 才拉满
            return [.init(temp: 45, duty: 10), .init(temp: 60, duty: 20),
                    .init(temp: 75, duty: 50), .init(temp: 85, duty: 100)]
        case .standard:
            return [.init(temp: 42, duty: 22), .init(temp: 58, duty: 38),
                    .init(temp: 72, duty: 65), .init(temp: 84, duty: 100)]
        case .performance:
            return [.init(temp: 38, duty: 35), .init(temp: 52, duty: 55),
                    .init(temp: 66, duty: 80), .init(temp: 78, duty: 100)]
        case .full:
            return [.init(temp: 0, duty: 100), .init(temp: 120, duty: 100)]
        case .manual, .custom:
            return nil
        }
    }

    var minDuty: Double {
        switch self {
        case .silent:      return 10
        case .standard:    return 22
        case .performance: return 35
        case .full:        return 100
        case .manual, .custom: return 20
        }
    }

    /// 温度指数平滑的时间常数（采样次数）。越大越稳、越不容易忽高忽低。
    var smooth: Int {
        switch self {
        case .silent:      return 6
        case .standard:    return 5
        case .performance: return 3
        case .full:        return 1
        case .manual, .custom: return 5
        }
    }

    var usesCurve: Bool { self != .manual }
}

// MARK: - 控制器

final class FanController: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var mode: ControlMode = .standard
    /// 曲线模式下的占空比下限（%）。切换模式时会重置为该模式的预设值，之后可手动微调。
    @Published var minDuty: Double = ControlMode.standard.minDuty
    @Published var selectedFans: Set<Int> = []
    @Published var useCPU = true
    @Published var useGPU = true
    @Published var cpuChoice: SensorChoice = SensorChoice.cpuChoices[0]
    @Published var gpuChoice: SensorChoice = SensorChoice.gpuChoices[0]
    @Published var manualDuty: [Int: Double] = [:]
    @Published var customPoints: [CurvePoint] = [
        .init(temp: 45, duty: 25), .init(temp: 65, duty: 60), .init(temp: 80, duty: 100)
    ]
    @Published var message: String = ""
    @Published var busy = false
    @Published var needsInstall = false
    @Published var appliedMode: ControlMode? = nil

    static let installedHelper = "/usr/local/sbin/fanctl"
    static let version = "1.2.0"

    /// 只读操作可以走任意一份 fanctl；写操作必须走已安装的那份（sudoers 只授权了它）。
    /// 环境变量 FANCTL_PATH 可覆盖，便于开发/预览时用未安装的新版 helper。
    private var readHelper: String {
        if let o = ProcessInfo.processInfo.environment["FANCTL_PATH"],
           FileManager.default.isExecutableFile(atPath: o) { return o }
        if FileManager.default.isExecutableFile(atPath: Self.installedHelper) { return Self.installedHelper }
        if let res = Bundle.main.resourceURL?.appendingPathComponent("fanctl").path,
           FileManager.default.isExecutableFile(atPath: res) { return res }
        let dev = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("WorkBuddy AI/2026-10-08-18-53-57/FanControl/helper/fanctl").path
        return dev
    }

    private var timer: Timer?
    init() {
        refresh()
        startPolling()
    }

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: 进程调用

    @discardableResult
    private func run(_ exe: String, _ args: [String]) -> (code: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let o = Pipe(), e = Pipe()
        p.standardOutput = o
        p.standardError = e
        do { try p.run() } catch {
            return (-1, "", "无法执行 \(exe): \(error.localizedDescription)")
        }
        let od = o.fileHandleForReading.readDataToEndOfFile()
        let ed = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus,
                String(data: od, encoding: .utf8) ?? "",
                String(data: ed, encoding: .utf8) ?? "")
    }

    @discardableResult
    private func runSudo(_ args: [String]) -> (code: Int32, out: String, err: String) {
        run("/usr/bin/sudo", ["-n", Self.installedHelper] + args)
    }

    // MARK: 读取状态

    /// 读一次状态。1.2 只有 `fanctl read` 一个只读子命令，很快，直接同步调。
    func refresh() {
        let helper = readHelper
        let r = run(helper, ["read"])
        if r.code == 0, let d = r.out.data(using: .utf8),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: d) {
            ingest(snap)
        } else {
            let err = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
            message = err.isEmpty ? "读取状态失败" : err
        }
    }

    private func ingest(_ snap: Snapshot) {
        let firstLoad = snapshot == nil
        snapshot = snap
        if firstLoad {
            // 默认勾选：有测速且在转的风扇，排除水泵
            let live = snap.fans.filter { $0.ch != snap.pumpChannel && $0.rpm > 0 }.map(\.ch)
            selectedFans = Set(live.isEmpty
                ? snap.fans.filter { $0.ch != snap.pumpChannel }.map(\.ch)
                : live)
            for f in snap.fans where f.ch != snap.pumpChannel {
                manualDuty[f.ch] = 40
            }
        }
        message = ""
    }

    // MARK: 应用

    private func curveString(_ pts: [CurvePoint]) -> String {
        pts.sorted { $0.temp < $1.temp }
           .map { "\(Int($0.temp.rounded())):\(Int($0.duty.rounded()))" }
           .joined(separator: " ")
    }

    func activeCurve() -> [CurvePoint] {
        if mode == .custom { return customPoints }
        return mode.curve ?? customPoints
    }

    func apply() {
        guard snapshot != nil else { return }
        let fans = selectedFans.sorted()
        guard !fans.isEmpty else { message = "请至少勾选一个风扇"; return }

        busy = true
        let isManual = (mode == .manual)

        DispatchQueue.global().async {
            var log: [String] = []

            if isManual {
                log.append(self.runSudo(["daemon", "stop"]).out)
                for ch in fans {
                    let d = Int((self.manualDuty[ch] ?? 40).rounded())
                    let r = self.runSudo(["duty", String(ch), String(d)])
                    log.append("ch\(ch) -> \(d)% \(r.code == 0 ? "ok" : "失败")")
                }
            } else {
                var conf = "# 由 FanControl 生成\n"
                conf += "fans = " + fans.map(String.init).joined(separator: ",") + "\n\n"
                let c = self.curveString(self.activeCurve())
                if self.useCPU { conf += "source = \(self.cpuChoice.keyString) : \(c)\n" }
                if self.useGPU { conf += "source = \(self.gpuChoice.keyString) : \(c)\n" }
                if !self.useCPU && !self.useGPU {
                    DispatchQueue.main.async { self.busy = false; self.message = "请至少勾选一个温度来源" }
                    return
                }
                conf += """
                \ninterval   = 2
                min_duty   = \(Int(self.minDuty.rounded()))
                smooth     = \(self.mode.smooth)
                fail_duty  = 100
                fail_limit = 3
                down_step  = 2
                hysteresis = 3

                """
                let tmp = "/tmp/fancontrol-gpufand.conf"
                try? conf.write(toFile: tmp, atomically: true, encoding: .utf8)
                let r1 = self.runSudo(["conf", tmp])
                let r2 = self.runSudo(["daemon", "restart"])
                log.append(r1.out.isEmpty ? r1.err : r1.out)
                log.append(r2.out.isEmpty ? r2.err : r2.out)
                if r1.code != 0 || r2.code != 0 {
                    log.append("提示：需要先安装辅助程序（见安装脚本）")
                }
            }

            let text = log.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                self.busy = false
                self.appliedMode = self.mode
                self.message = text.isEmpty ? "已应用：\(self.mode.label)" : "已应用：\(self.mode.label) · \(text)"
                self.needsInstall = text.contains("安装")
                self.refresh()
            }
        }
    }

    func returnToBIOS() {
        busy = true
        DispatchQueue.global().async {
            self.runSudo(["daemon", "stop"])
            let r = self.runSudo(["bios", "all"])
            DispatchQueue.main.async {
                self.busy = false
                self.appliedMode = nil
                self.message = r.code == 0 ? "已交还 BIOS 控制" : "交还失败：\(r.err)"
                self.refresh()
            }
        }
    }

    func setDutyLive(ch: Int, duty: Double) {
        manualDuty[ch] = duty
        guard mode == .manual else { return }
        DispatchQueue.global().async {
            self.runSudo(["duty", String(ch), String(Int(duty.rounded()))])
        }
    }

    // MARK: 显示辅助

    var cpuTemp: Double? { hottest(cpuChoice.keys) }
    var gpuTemp: Double? { hottest(gpuChoice.keys) }

    /// 只读的显卡监控数据（风扇转速/占空比/温度/功耗/频率/占用）。
    /// 注意：这与上面的 gpuTemp 不是一回事 —— gpuTemp 来自 SMC（RadeonSensor），
    /// 这里来自 IORegistry，用于显示显卡自身风扇的状态。
    var gpu: GpuState? { snapshot?.gpu }

    /// 显卡风扇转速，用于顶栏
    var gpuFanRPM: Double? { snapshot?.gpu?.fanRPM }

    /// 水泵通道不是从 fancontrol.conf 读来的 —— 换机器后必须确认，
    /// 否则可能把真水泵锁死、或把普通风扇放开调速
    var pumpUnconfirmed: Bool {
        guard let s = snapshot else { return false }
        return !(s.pumpConfigured ?? false)
    }

    /// 一组传感器键里最热的那个（守护进程也是这个逻辑）
    private func hottest(_ keys: [String]) -> Double? {
        let vals = keys.compactMap { snapshot?.sensor($0) }
        return vals.max()
    }

    var statusText: String {
        guard let s = snapshot else { return "读取中…" }
        if let m = appliedMode, s.service.running { return "自动 · \(m.label)" }
        if s.service.running { return "自动调速运行中" }
        let manual = s.fans.contains { $0.isManual }
        if manual { return "手动" }
        return "BIOS 控制"
    }

    var statusColor: StatusColor {
        guard let s = snapshot else { return .grey }
        if s.service.running { return .green }
        if s.fans.contains(where: { $0.isManual }) { return .orange }
        return .grey
    }

    enum StatusColor { case green, orange, grey }
}

// MARK: - 温度来源候选

/// 一个温度来源：可以是一个键，也可以是多个键（守护进程取其中最热的那个）
struct SensorChoice: Identifiable, Hashable {
    let keys: [String]
    let short: String        // 按钮上的短标签
    let label: String        // 悬停说明
    var id: String { keys.joined(separator: ",") }
    /// 写进 gpufand 配置的形式： KEY[,KEY...]
    var keyString: String { keys.joined(separator: ",") }

    /// CPU 默认用 8 个核心传感器 —— 它们平滑；
    /// TC0P/TC0D 是封装/晶片，会随睿频瞬时冲高（实测 33→65→35°C 来回跳），
    /// 直接拿来控速会让风扇几秒内反复拉高又降下来，很吵。
    static let cpuChoices: [SensorChoice] = [
        .init(keys: ["TC0C", "TC1C", "TC2C", "TC3C", "TC4C", "TC5C", "TC6C", "TC7C"],
              short: "8 核心",
              label: "CPU 8 个核心，取最热 —— 平滑，推荐"),
        .init(keys: ["TC0P"],
              short: "封装",
              label: "CPU 封装 (TC0P) —— 反应快但抖动大，容易让风扇忽高忽低"),
    ]
    static let gpuChoices: [SensorChoice] = [
        .init(keys: ["TG0D", "TG0P"],
              short: "核心+板边",
              label: "GPU 核心与板边，取最热"),
        .init(keys: ["TG0D"],
              short: "核心",
              label: "GPU 核心 (TG0D)"),
    ]
}
