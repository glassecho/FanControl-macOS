import Foundation
import Combine
import ServiceManagement

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

/// 传感器面板里的一项（由 SensorState 挑出来的）
struct SensorItem: Identifiable {
    let key: String
    let label: String
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

// MARK: - 系统监控数据（fanctl sys，只读）

struct CpuInfo: Decodable {
    let cores: Int
    let total: Double
    let user: Double
    let system: Double
    let load: [Double]
    let brand: String
    let uptime: Double
    let perCore: [Double]
}

struct MemInfo: Decodable {
    let total: Double
    let used: Double
    let wired: Double
    let compressed: Double
    let swapTotal: Double
    let swapUsed: Double

    var ratio: Double { total > 0 ? min(1, used / total) : 0 }
}

struct DiskInfo: Decodable, Identifiable {
    let mount: String
    let total: Double
    let free: Double
    var id: String { mount }

    var used: Double { max(0, total - free) }
    var ratio: Double { total > 0 ? min(1, used / total) : 0 }
    /// 挂载点显示名：根卷给个中文名，外置卷用卷名
    var name: String {
        if mount == "/" { return "系统盘" }
        return (mount as NSString).lastPathComponent
    }
}

struct NetInfo: Decodable {
    let iface: String
    let `in`: Double
    let out: Double
}

struct ProcInfo: Decodable, Identifiable {
    let pid: Int
    let name: String
    let cpu: Double
    var id: Int { pid }
}

struct SysInfo: Decodable {
    let ok: Bool
    let cpu: CpuInfo
    let mem: MemInfo
    let disk: [DiskInfo]
    let net: NetInfo
    let procs: [ProcInfo]
}

/// 监控页上可以单独开关的面板
enum PanelKind: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, storage, network, processes, sensors, system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cpu:       return "CPU"
        case .gpu:       return "显卡"
        case .memory:    return "内存"
        case .storage:   return "存储"
        case .network:   return "网络"
        case .processes: return "进程"
        case .sensors:   return "传感器"
        case .system:    return "系统"
        }
    }

    var symbol: String {
        switch self {
        case .cpu:       return "cpu"
        case .gpu:       return "display"
        case .memory:    return "memorychip"
        case .storage:   return "internaldrive"
        case .network:   return "network"
        case .processes: return "list.bullet.rectangle"
        case .sensors:   return "thermometer.medium"
        case .system:    return "info.circle"
        }
    }

    var detail: String {
        switch self {
        case .cpu:       return "总占用 · 每个核心 · 负载"
        case .gpu:       return "显卡风扇 · 温度 · 功耗"
        case .memory:    return "已用 · 联动 · 压缩 · 交换"
        case .storage:   return "各卷已用空间"
        case .network:   return "上行 / 下行速率"
        case .processes: return "占用最高的进程"
        case .sensors:   return "CPU / GPU 温度"
        case .system:    return "机型 · 运行时间 · 负载"
        }
    }
}

/// 菜单栏（状态栏）里可以显示的项目。每一项都能单独开关。
enum MenuBarItem: String, CaseIterable, Identifiable {
    case icon, cpuTemp, gpuTemp, cpuLoad, memory, fanRPM, gpuFan, network

    var id: String { rawValue }

    var label: String {
        switch self {
        case .icon:    return "风扇图标"
        case .cpuTemp: return "CPU 温度"
        case .gpuTemp: return "GPU 温度"
        case .cpuLoad: return "CPU 占用"
        case .memory:  return "内存"
        case .fanRPM:  return "风扇转速"
        case .gpuFan:  return "显卡风扇"
        case .network: return "网络"
        }
    }

    var symbol: String {
        switch self {
        case .icon:    return "fanblades.fill"
        case .cpuTemp: return "cpu"
        case .gpuTemp: return "display"
        case .cpuLoad: return "speedometer"
        case .memory:  return "memorychip"
        case .fanRPM:  return "wind"
        case .gpuFan:  return "fanblades"
        case .network: return "arrow.up.arrow.down"
        }
    }

    var detail: String {
        switch self {
        case .icon:    return "只显示一个图标"
        case .cpuTemp: return "最热核心的温度"
        case .gpuTemp: return "显卡温度"
        case .cpuLoad: return "总占用率"
        case .memory:  return "已用比例"
        case .fanRPM:  return "转得最快的受控风扇"
        case .gpuFan:  return "显卡自身风扇转速"
        case .network: return "下行速率"
        }
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

/// 子进程输出的小容器。给并发读取 stdout / stderr 的两个线程各用一个，
/// 避免在并发闭包里直接捕获 var。
private final class PipeBox: @unchecked Sendable {
    var data = Data()
}

final class FanController: ObservableObject {
    @Published var snapshot: Snapshot?
    /// 系统监控数据（CPU/内存/磁盘/网络/进程）—— 只读
    @Published var sys: SysInfo?
    /// 监控页上开启的面板，持久化到 UserDefaults
    @Published var enabledPanels: Set<PanelKind> = Set(PanelKind.allCases) {
        didSet { Self.savePanels(enabledPanels) }
    }
    /// 菜单栏上显示的项目，持久化到 UserDefaults
    @Published var menuBarItems: Set<MenuBarItem> = [.icon, .cpuTemp, .gpuTemp] {
        didSet { Self.saveMenuBar(menuBarItems) }
    }
    /// 网络速率（字节/秒），由两次采样差值算出
    @Published var netDown: Double?
    @Published var netUp: Double?
    /// CPU 总占用历史，画迷你走势图用
    @Published var cpuHistory: [Double] = []

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

    /// 版本号的**唯一来源**是 Info.plist 的 CFBundleShortVersionString。
    /// 以前这里、Info.plist、make-pkg.sh 三处各写一遍，改了 plist 忘了改这里，
    /// 界面上就会显示旧版本号。现在统一从 Bundle 读，改版本只需动 Info.plist。
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }

    /// 只读操作可以走任意一份 fanctl；写操作必须走已安装的那份（sudoers 只授权了它）。
    /// 环境变量 FANCTL_PATH 可覆盖，便于开发/预览时用未安装的新版 helper。
    private var readHelper: String {
        if let o = ProcessInfo.processInfo.environment["FANCTL_PATH"],
           FileManager.default.isExecutableFile(atPath: o) { return o }
        if FileManager.default.isExecutableFile(atPath: Self.installedHelper) { return Self.installedHelper }
        if let res = Bundle.main.resourceURL?.appendingPathComponent("fanctl").path,
           FileManager.default.isExecutableFile(atPath: res) { return res }
        #if DEBUG
        // 开发期兜底。包在 #if DEBUG 里，发布版不会把本机路径编进二进制
        // （否则 `strings FanControl | grep WorkBuddy` 就能看到开发目录）。
        let dev = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("WorkBuddy AI/2026-10-08-18-53-57/FanControl/helper/fanctl").path
        if FileManager.default.isExecutableFile(atPath: dev) { return dev }
        #endif
        return Self.installedHelper
    }

    private var timer: Timer?
    private let work = DispatchQueue(label: "com.fancontrol.refresh", qos: .utility)
    private var refreshing = false

    /// 上一次网络采样，用来算速率
    private var lastNet: (iface: String, inBytes: Double, outBytes: Double, at: Date)?

    private static let panelsKey = "fancontrol.enabledPanels"
    private static let menuBarKey = "fancontrol.menuBarItems"

    static func loadPanels() -> Set<PanelKind> {
        guard let raw = UserDefaults.standard.array(forKey: panelsKey) as? [String] else {
            return Set(PanelKind.allCases)      // 首次运行：全开
        }
        return Set(raw.compactMap { PanelKind(rawValue: $0) })
    }

    private static func savePanels(_ s: Set<PanelKind>) {
        UserDefaults.standard.set(s.map(\.rawValue), forKey: panelsKey)
    }

    static func loadMenuBar() -> Set<MenuBarItem> {
        guard let raw = UserDefaults.standard.array(forKey: menuBarKey) as? [String] else {
            return [.icon, .cpuTemp, .gpuTemp]  // 首次运行：图标 + CPU/GPU 温度
        }
        return Set(raw.compactMap { MenuBarItem(rawValue: $0) })
    }

    private static func saveMenuBar(_ s: Set<MenuBarItem>) {
        UserDefaults.standard.set(s.map(\.rawValue), forKey: menuBarKey)
    }

    init() {
        enabledPanels = Self.loadPanels()
        menuBarItems = Self.loadMenuBar()
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

        // stdout 与 stderr 必须**同时**排空。
        // 若按「先读完 stdout、再读 stderr」的顺序，子进程一旦把 stderr 写满管道缓冲区
        // （macOS 上约 64KB），它会阻塞在 write 上永不退出，stdout 也就永远等不到 EOF
        // —— 两边互相等待，死锁。这里各起一个后台线程并行读，彻底避开这个陷阱。
        let outBox = PipeBox(), errBox = PipeBox()
        let g = DispatchGroup()
        g.enter()
        DispatchQueue.global(qos: .utility).async {
            outBox.data = o.fileHandleForReading.readDataToEndOfFile()
            g.leave()
        }
        g.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.data = e.fileHandleForReading.readDataToEndOfFile()
            g.leave()
        }
        g.wait()
        p.waitUntilExit()

        return (p.terminationStatus,
                String(data: outBox.data, encoding: .utf8) ?? "",
                String(data: errBox.data, encoding: .utf8) ?? "")
    }

    @discardableResult
    private func runSudo(_ args: [String]) -> (code: Int32, out: String, err: String) {
        run("/usr/bin/sudo", ["-n", Self.installedHelper] + args)
    }

    // MARK: 读取状态

    /// 读状态放在后台队列 —— `fanctl sys` 内部有 400ms 采样窗口，
    /// 放主线程会把界面卡住。两件事做完一起回主线程更新。
    func refresh() {
        if refreshing { return }
        refreshing = true
        let helper = readHelper

        work.async { [weak self] in
            guard let self = self else { return }

            let r = self.run(helper, ["read"])
            var snap: Snapshot?
            if r.code == 0, let d = r.out.data(using: .utf8) {
                snap = try? JSONDecoder().decode(Snapshot.self, from: d)
            }

            let s = self.run(helper, ["sys"])
            var sysInfo: SysInfo?
            if s.code == 0, let d = s.out.data(using: .utf8) {
                sysInfo = try? JSONDecoder().decode(SysInfo.self, from: d)
            }

            let err = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                self.refreshing = false
                if let snap = snap { self.ingest(snap) }
                else { self.message = err.isEmpty ? "读取状态失败" : err }
                if let sysInfo = sysInfo { self.ingest(sysInfo) }
            }
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

    private func ingest(_ s: SysInfo) {
        sys = s

        // 网络速率：与上一次采样做差（间隔约等于轮询周期，比 400ms 窗口平滑）
        let now = Date()
        if let last = lastNet, last.iface == s.net.iface {
            let dt = now.timeIntervalSince(last.at)
            if dt > 0.2 {
                netDown = max(0, (s.net.in - last.inBytes) / dt)
                netUp   = max(0, (s.net.out - last.outBytes) / dt)
            }
        }
        lastNet = (s.net.iface, s.net.in, s.net.out, now)

        // CPU 走势
        cpuHistory.append(s.cpu.total)
        if cpuHistory.count > 90 { cpuHistory.removeFirst(cpuHistory.count - 90) }
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
                // 用唯一文件名 + 用户私有临时目录：
                // 固定路径会被多实例互相覆盖，且 /tmp 下的文件默认 644、其他用户可读
                let tmp = NSTemporaryDirectory() + "fancontrol-gpufand-\(UUID().uuidString).conf"
                try? conf.write(toFile: tmp, atomically: true, encoding: .utf8)
                let r1 = self.runSudo(["conf", tmp])
                try? FileManager.default.removeItem(atPath: tmp)
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

    // MARK: 监控页用的便捷访问

    var cpuInfo: CpuInfo? { sys?.cpu }
    var memInfo: MemInfo? { sys?.mem }
    var disks: [DiskInfo] { sys?.disk ?? [] }
    var procs: [ProcInfo] { sys?.procs ?? [] }
    var netIface: String? { sys?.net.iface }

    /// 传感器面板要显示的项：CPU 各核心 + GPU 核心/板边
    ///
    /// 核心键是 `TC<n>C`。**不要写死 `0..<8`** —— 不同机器暴露的核心数不一样，
    /// 写死 8 会漏掉第 9 个及以后。这里按实际存在的键动态发现，并按序号排序。
    var sensorItems: [SensorItem] {
        var out: [SensorItem] = []

        let cores: [(n: Int, key: String, value: Double)] = (snapshot?.sensors ?? [])
            .compactMap { s in
                guard s.key.hasPrefix("TC"), s.key.hasSuffix("C"), s.value > 0 else { return nil }
                guard let n = Int(s.key.dropFirst(2).dropLast()) else { return nil }
                return (n, s.key, s.value)
            }
            .sorted { $0.n < $1.n }

        for c in cores {
            out.append(SensorItem(key: c.key, label: "核心 \(c.n)", value: c.value))
        }

        if let v = snapshot?.sensor("TG0D") { out.append(SensorItem(key: "TG0D", label: "GPU 核心", value: v)) }
        if let v = snapshot?.sensor("TG0P") { out.append(SensorItem(key: "TG0P", label: "GPU 板边", value: v)) }
        return out
    }

    /// 面板开关
    func panel(_ k: PanelKind) -> Bool { enabledPanels.contains(k) }
    func togglePanel(_ k: PanelKind) {
        if enabledPanels.contains(k) { enabledPanels.remove(k) } else { enabledPanels.insert(k) }
    }
    var enabledPanelList: [PanelKind] { PanelKind.allCases.filter { enabledPanels.contains($0) } }

    // MARK: 菜单栏

    func menuBar(_ k: MenuBarItem) -> Bool { menuBarItems.contains(k) }

    func toggleMenuBar(_ k: MenuBarItem) {
        if menuBarItems.contains(k) { menuBarItems.remove(k) } else { menuBarItems.insert(k) }
    }

    /// 按固定顺序排列（allCases 的顺序），标签和面板共用
    var menuBarItemList: [MenuBarItem] {
        MenuBarItem.allCases.filter { menuBarItems.contains($0) }
    }

    /// 受控风扇里转得最快的那个（排除水泵）—— 菜单栏上显示它最有意义
    var topFanRPM: Double? {
        guard let s = snapshot else { return nil }
        let live = s.fans.filter { $0.ch != s.pumpChannel && $0.rpm > 0 }
        if let m = live.map(\.rpm).max() { return m }
        return s.fans.filter { $0.ch != s.pumpChannel }.map(\.rpm).max()
    }

    /// 只读的显卡监控数据（风扇转速/占空比/温度/功耗/频率/占用）。
    /// 注意：这与上面的 gpuTemp 不是一回事 —— gpuTemp 来自 SMC（RadeonSensor），
    /// 这里来自 IORegistry，用于显示显卡自身风扇的状态。
    var gpu: GpuState? { snapshot?.gpu }

    /// 显卡风扇转速，用于顶栏
    var gpuFanRPM: Double? { snapshot?.gpu?.fanRPM }

    // MARK: 开机自启

    /// 是否已注册为登录项。用 SMAppService（macOS 13+）—— 系统会在
    /// 「系统设置 → 通用 → 登录项」里列出它，用户也能自己关掉，比手写 LaunchAgent 正规。
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    func refreshLaunchAtLogin() {
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
            message = on
                ? "已设为开机自启 —— 开机后会自动打开主窗口，关掉即可，菜单栏图标会保留"
                : "已关闭开机自启"
        } catch {
            message = "设置开机自启失败：\(error.localizedDescription)"
        }
        refreshLaunchAtLogin()
    }

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
