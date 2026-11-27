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
        case 1: return L.fanModeManualRPM
        case 2: return L.fanModeManualDuty
        default: return L.fanModeBIOS
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
        if mount == "/" { return L.systemDisk }
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
        case .cpu:       return L.panelCPU
        case .gpu:       return L.panelGPU
        case .memory:    return L.panelMemory
        case .storage:   return L.panelStorage
        case .network:   return L.panelNetwork
        case .processes: return L.panelProcesses
        case .sensors:   return L.panelSensors
        case .system:    return L.panelSystem
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
        case .cpu:       return L.panelCPUDetail
        case .gpu:       return L.panelGPUDetail
        case .memory:    return L.panelMemoryDetail
        case .storage:   return L.panelStorageDetail
        case .network:   return L.panelNetworkDetail
        case .processes: return L.panelProcessesDetail
        case .sensors:   return L.panelSensorsDetail
        case .system:    return L.panelSystemDetail
        }
    }
}

/// 菜单栏（状态栏）里可以显示的项目。每一项都能单独开关。
enum MenuBarItem: String, CaseIterable, Identifiable {
    case icon, cpuTemp, gpuTemp, cpuLoad, memory, fanRPM, gpuFan, network

    var id: String { rawValue }

    var label: String {
        switch self {
        case .icon:    return L.mbIcon
        case .cpuTemp: return L.mbCPUTemp
        case .gpuTemp: return L.mbGPUTemp
        case .cpuLoad: return L.mbCPULoad
        case .memory:  return L.mbMemory
        case .fanRPM:  return L.mbFanRPM
        case .gpuFan:  return L.mbGPUFan
        case .network: return L.mbNetwork
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
        case .icon:    return L.mbIconDetail
        case .cpuTemp: return L.mbCPUTempDetail
        case .gpuTemp: return L.mbGPUTempDetail
        case .cpuLoad: return L.mbCPULoadDetail
        case .memory:  return L.mbMemoryDetail
        case .fanRPM:  return L.mbFanRPMDetail
        case .gpuFan:  return L.mbGPUFanDetail
        case .network: return L.mbNetworkDetail
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
        case .silent:      return L.modeSilent
        case .standard:    return L.modeStandard
        case .performance: return L.modePerformance
        case .full:        return L.modeFull
        case .manual:      return L.modeManual
        case .custom:      return L.modeCustom
        }
    }

    var detail: String {
        switch self {
        case .silent:      return L.modeSilentDetail
        case .standard:    return L.modeStandardDetail
        case .performance: return L.modePerformanceDetail
        case .full:        return L.modeFullDetail
        case .manual:      return L.modeManualDetail
        case .custom:      return L.modeCustomDetail
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

    // MARK: 显存状态

    /// 剩余显存（字节）。nil = 读不到（核显机器 / 无独显 / ioreg 不可用）
    @Published private(set) var vramFreeBytes: Int64?
    /// 显存总量（字节），由「剩余 + 占用 + 可回收」推出来，用于算占用率
    @Published private(set) var vramTotalBytes: Int64?
    /// 显存告急。此时主动降级：**停止重绘走势图**、拉长轮询间隔。
    ///
    /// 为什么需要这个：macOS 没有 Windows WDDM 那层显存虚拟化，一个程序把显存占满
    /// （典型是 Lightroom 的 AI 推理，只进不出），别的程序一申请就失败 ——
    /// 表现就是本 app 在 SwiftUI 渲染时被系统直接干掉。降级不解决问题本身，
    /// 但能让本 app 在显存见底时不跟着死。
    @Published private(set) var vramLow = false

    /// 进入低显存模式的阈值：1 GB。
    ///
    /// 可用环境变量覆盖，方便在显存宽裕的机器上**强制验证降级路径**
    /// （降级分支平时根本不会走到，不测等于没写）：
    /// ```
    /// launchctl setenv FANCONTROL_VRAM_LOW_MB 999999   # 立刻进入降级态
    /// open -n /Applications/FanControl.app
    /// launchctl unsetenv FANCONTROL_VRAM_LOW_MB
    /// ```
    static let vramLowBytes: Int64 = {
        if let s = ProcessInfo.processInfo.environment["FANCONTROL_VRAM_LOW_MB"],
           let mb = Int64(s), mb > 0 {
            return mb * 1_048_576
        }
        return 1_024 * 1_024 * 1_024
    }()
    /// 恢复正常模式的阈值：低阈值的两倍。留一倍回差，避免在边界上反复抖动
    static let vramRecoverBytes: Int64 = vramLowBytes * 2

    /// 轮询间隔（秒），可调并持久化。
    /// 旧版写死 2 秒 —— 8 个面板每 2 秒全量重绘一次，显存紧张时等于持续敲门。
    @Published var pollInterval: Double = 3.0 {
        didSet {
            guard pollInterval != oldValue else { return }
            UserDefaults.standard.set(pollInterval, forKey: Self.pollKey)
            if timer != nil { startPolling() }
        }
    }

    /// 低显存时实际用的间隔：不低于 8 秒。降级期间少画一次就少一次风险
    var effectiveInterval: Double { vramLow ? max(pollInterval, 8.0) : pollInterval }

    /// 显存占用率（0…1），读不到总量时给 nil
    var vramUsedRatio: Double? {
        guard let f = vramFreeBytes, let t = vramTotalBytes, t > 0 else { return nil }
        return min(max(1.0 - Double(f) / Double(t), 0), 1)
    }

    @Published var mode: ControlMode = .standard
    /// 曲线模式下的占空比下限（%）。切换模式时会重置为该模式的预设值，之后可手动微调。
    @Published var minDuty: Double = ControlMode.standard.minDuty
    @Published var selectedFans: Set<Int> = []
    @Published var useCPU = true
    @Published var useGPU = true
    /// 温度来源候选。**按机器实际暴露的传感器生成** —— 核心数不是 8 的机器
    /// 以前会带上不存在的 TC6C/TC7C，按钮上还写着「8 核心」。
    @Published private(set) var cpuChoices: [SensorChoice] = SensorChoice.cpuChoices(available: [])
    @Published private(set) var gpuChoices: [SensorChoice] = SensorChoice.gpuChoices(available: [])
    @Published var cpuChoice: SensorChoice = .placeholder
    @Published var gpuChoice: SensorChoice = .placeholder
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
        // 离屏渲染编出来的是裸二进制、没有 Info.plist，Bundle 里读不到版本号。
        // 给它留一个环境变量覆盖（render.swift 会传），免得预览图上前端显示「v?」。
        if let o = ProcessInfo.processInfo.environment["FANCONTROL_VERSION"], !o.isEmpty { return o }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L.unknown
    }

    /// 构建号（Info.plist 的 CFBundleVersion）。同一个版本号可能编出多个包，
    /// 报问题时带上它能分清是哪一次构建 —— 悬停底栏版本号即可看到。
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    /// 「v1.5.1」/「v1.5.1 (17)」，构建号缺失时只显示版本号。
    static var versionText: String {
        build.isEmpty ? "v\(version)" : "v\(version) (\(build))"
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
    private var vramTimer: Timer?
    private let work = DispatchQueue(label: "com.fancontrol.refresh", qos: .utility)
    private var refreshing = false

    /// 上一次网络采样，用来算速率
    private var lastNet: (iface: String, inBytes: Double, outBytes: Double, at: Date)?

    private static let panelsKey = "fancontrol.enabledPanels"
    private static let menuBarKey = "fancontrol.menuBarItems"
    private static let pollKey = "fancontrol.pollInterval"

    static func loadPanels() -> Set<PanelKind> {
        guard let raw = UserDefaults.standard.array(forKey: panelsKey) as? [String] else {
            // 首次运行：**不再全开 8 个面板**。
            // 每块面板都是一套 SwiftUI 图层，全开等于把渲染面积拉满，
            // 显存紧张时最先倒的就是它。默认只留最常看的四个。
            return [.cpu, .gpu, .sensors, .memory]
        }
        return Set(raw.compactMap { PanelKind(rawValue: $0) })
    }

    static func loadPollInterval() -> Double {
        let v = UserDefaults.standard.double(forKey: pollKey)
        // 0 表示没存过；顺手夹到合理区间，防止有人写坏 plist 把轮询搞成 0.01 秒
        guard v > 0 else { return 3.0 }
        return min(max(v, 1.0), 30.0)
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
        pollInterval = Self.loadPollInterval()
        refresh()
        startPolling()
        startVRAMPolling()
    }

    func startPolling() {
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: effectiveInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // 容差让系统把唤醒攒到一起发，省电也少一次渲染机会
        t.tolerance = min(1.0, effectiveInterval * 0.2)
        timer = t
    }

    // MARK: 显存轮询

    /// 显存单独一条定时器：15 秒一次就够，不该拖慢温度主轮询。
    /// 单独跑还有个好处 —— 窗口没开、主轮询在降级时，显存状态照样更新。
    func startVRAMPolling() {
        vramTimer?.invalidate()
        updateVRAM()            // 立刻取一次，别等第一个周期
        let t = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.updateVRAM()
        }
        t.tolerance = 3.0
        vramTimer = t
    }

    /// 读一次显存状态。要起一个 `ioreg` 子进程，放后台队列，别堵主线程。
    func updateVRAM() {
        work.async { [weak self] in
            guard let self = self else { return }
            let (free, total) = self.readVRAM()
            DispatchQueue.main.async {
                self.vramFreeBytes = free
                self.vramTotalBytes = total
                guard let f = free else { return }

                let wasLow = self.vramLow
                if !wasLow, f < Self.vramLowBytes { self.vramLow = true }
                else if wasLow, f > Self.vramRecoverBytes { self.vramLow = false }

                // 模式翻转 → 轮询间隔跟着变，重排定时器
                if self.vramLow != wasLow, self.timer != nil { self.startPolling() }
            }
        }
    }

    /// 解析 `ioreg -r -c IOAccelerator -d 1 -w 0`。
    ///
    /// 一台机器可能有多块加速器（核显 + 独显）。**取「总容量最大」的那块**，
    /// 也就是 Lightroom / 游戏真正在用的独显 —— 不能取「剩余最少」，
    /// 否则核显那点显存会天天误报告急。
    private func readVRAM() -> (free: Int64?, total: Int64?) {
        let r = run("/usr/sbin/ioreg", ["-r", "-c", "IOAccelerator", "-d", "1", "-w", "0"])
        guard r.code == 0, !r.out.isEmpty else { return (nil, nil) }

        func num(_ s: String, _ key: String) -> Int64? {
            guard let rng = s.range(of: "\"\(key)\"=") else { return nil }
            let digits = s[rng.upperBound...].prefix { $0.isNumber }
            return digits.isEmpty ? nil : Int64(digits)
        }

        // **按节点切块**再各取各的，不能按出现顺序配对 ——
        // ioreg 里 `vramFreeBytes` 排在 `inUseVidMemoryBytes` **之后**，
        // 而且同一个节点的统计还会重复输出一遍。顺序配对必然错位。
        var devices: [(free: Int64, used: Int64)] = []
        for block in r.out.components(separatedBy: "\n+-o ") {
            guard let free = num(block, "vramFreeBytes") else { continue }
            let used = (num(block, "inUseVidMemoryBytes") ?? 0)
                     + (num(block, "orphanedReusableVidMemoryBytes") ?? 0)
                     + (num(block, "orphanedNonReusableVidMemoryBytes") ?? 0)
            devices.append((free, used))
        }

        guard let dev = devices.max(by: { ($0.free + $0.used) < ($1.free + $1.used) }) else {
            return (nil, nil)
        }
        // 总量 = 剩余 + 占用。驱动还有少量保留未计入，所以略小于物理显存，算占用率够用
        let total = dev.free + dev.used
        return (dev.free, total > 0 ? total : nil)
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
            return (-1, "", L.cannotRun(exe, error.localizedDescription))
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
                else { self.message = err.isEmpty ? L.msgReadFailed : err }
                if let sysInfo = sysInfo { self.ingest(sysInfo) }
            }
        }
    }

    private func ingest(_ snap: Snapshot) {
        let firstLoad = snapshot == nil
        snapshot = snap
        refreshSensorChoices(from: snap)
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

    /// 换机器、换 kext、或 SMP 核心数变化后，可用传感器会变，候选列表跟着重建。
    /// 用户已选的那组只要仍然存在就保持不变 —— 按 key 集合匹配，不按数组下标，
    /// 否则「封装」在列表里的位置一变，选择就会莫名其妙跳到别处。
    private func refreshSensorChoices(from snap: Snapshot) {
        let keys = Set(snap.sensors.map(\.key))

        let cpu = SensorChoice.cpuChoices(available: keys)
        if cpu.map(\.id) != cpuChoices.map(\.id) {
            let keep = cpuChoice.id
            cpuChoices = cpu
            cpuChoice = cpu.first { $0.id == keep } ?? cpu[0]
        }

        let gpu = SensorChoice.gpuChoices(available: keys)
        if gpu.map(\.id) != gpuChoices.map(\.id) {
            let keep = gpuChoice.id
            gpuChoices = gpu
            gpuChoice = gpu.first { $0.id == keep } ?? gpu[0]
        }
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

        // CPU 走势。**必须挡住 NaN/∞** —— `helper` 偶尔会在采样窗口没采满时
        // 吐出 "nan"，一旦进了数组就会一路传进 Path 的坐标里，
        // CoreGraphics 拿到 NaN 是未定义行为，正是这类崩溃的经典入口。
        let pct = s.cpu.total.isFinite ? min(max(s.cpu.total, 0), 100) : 0
        cpuHistory.append(pct)
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
        guard !fans.isEmpty else { message = L.msgNeedFan; return }

        busy = true
        let isManual = (mode == .manual)

        DispatchQueue.global().async {
            var log: [String] = []
            /// 辅助程序没装、或 sudoers 没配 —— 由**退出码**判断。
            /// 以前是 `text.contains("安装")`：文案一改就失效，界面切成英文后更是必然失效。
            var helperMissing = false

            if isManual {
                log.append(self.runSudo(["daemon", "stop"]).out)
                for ch in fans {
                    let d = Int((self.manualDuty[ch] ?? 40).rounded())
                    let r = self.runSudo(["duty", String(ch), String(d)])
                    if r.code != 0 { helperMissing = true }
                    log.append(r.code == 0 ? L.logOK(ch, d) : L.logFail(ch, d))
                }
            } else {
                var conf = "# generated by FanControl\n"
                conf += "fans = " + fans.map(String.init).joined(separator: ",") + "\n\n"
                let c = self.curveString(self.activeCurve())
                if self.useCPU { conf += "source = \(self.cpuChoice.keyString) : \(c)\n" }
                if self.useGPU { conf += "source = \(self.gpuChoice.keyString) : \(c)\n" }
                if !self.useCPU && !self.useGPU {
                    DispatchQueue.main.async { self.busy = false; self.message = L.msgNeedTempSource }
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
                    log.append(L.msgNeedInstall)
                    helperMissing = true
                }
            }

            let text = log.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                self.busy = false
                self.appliedMode = self.mode
                self.message = text.isEmpty ? L.applied(self.mode.label) : L.appliedWith(self.mode.label, text)
                self.needsInstall = helperMissing
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
                self.message = r.code == 0 ? L.msgReturnedBIOS : L.returnFailed(r.err)
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
            out.append(SensorItem(key: c.key, label: L.core(c.n), value: c.value))
        }

        if let v = snapshot?.sensor("TG0D") { out.append(SensorItem(key: "TG0D", label: L.gpuCoreSensor, value: v)) }
        if let v = snapshot?.sensor("TG0P") { out.append(SensorItem(key: "TG0P", label: L.gpuEdgeSensor, value: v)) }
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
            message = on ? L.msgLaunchOn : L.msgLaunchOff
        } catch {
            message = L.launchFailed(error.localizedDescription)
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
        guard let s = snapshot else { return L.reading }
        if let m = appliedMode, s.service.running { return L.autoWith(m.label) }
        if s.service.running { return L.statusAutoRunning }
        let manual = s.fans.contains { $0.isManual }
        if manual { return L.statusManual }
        return L.statusBIOS
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

    /// 首次采样之前用的占位：没有任何键，界面显示「—」。
    ///
    /// **不要拿一个真实键充当占位。** 之前 `cpuChoice` 初值是
    /// `cpuChoices(available: [])[0]`，也就是 `["TC0P"]`；等真实传感器列表刷新上来，
    /// 「保留原选择」按 key 匹配，`TC0P` 正好命中「封装」——默认项就被顶成了封装，
    /// 核心那组反而选不中。占位的 id 是空串，永远匹配不上，刷新时自然落回第一项。
    static let placeholder = SensorChoice(keys: [], short: "—", label: "")

    /// CPU 默认用**核心**传感器 —— 它们平滑；
    /// TC0P/TC0D 是封装/晶片，会随睿频瞬时冲高（实测 33→65→35°C 来回跳），
    /// 直接拿来控速会让风扇几秒内反复拉高又降下来，很吵。
    ///
    /// **键必须按机器实际暴露的来。** 以前这里写死 `TC0C…TC7C` 八个键，
    /// 换一台核心数不是 8 的机器就会带上不存在的键。守护进程本身是安全的
    /// （`gpufand.c` 校验阶段会把不存在的键剔掉、并打一行 "not present, ignored"），
    /// 但配置里留着一堆废键、按钮上还写着「8 核心」，都是错的。
    /// 现在从 `snapshot.sensors` 动态生成，机器有几个核心就列几个。
    static func cpuChoices(available: Set<String>) -> [SensorChoice] {
        var out: [SensorChoice] = []

        let cores = coreKeys(available: available)
        if !cores.isEmpty {
            out.append(.init(keys: cores,
                             short: L.sensorCPUCores(cores.count),
                             label: L.sensorCPUCoresLabel(cores.count)))
        }
        if available.contains("TC0P") {
            out.append(.init(keys: ["TC0P"],
                             short: L.sensorCPUPackage,
                             label: L.sensorCPUPackageLabel))
        }
        // 两种都没有（没装 SMCSuperIO、或键名不是这套）时留一个占位，
        // 让界面至少能显示「—」，而不是整块消失。
        if out.isEmpty {
            out.append(.init(keys: ["TC0P"],
                             short: L.sensorCPUPackage,
                             label: L.sensorCPUPackageLabel))
        }
        return out
    }

    static func gpuChoices(available: Set<String>) -> [SensorChoice] {
        var out: [SensorChoice] = []
        let hasD = available.contains("TG0D"), hasP = available.contains("TG0P")
        if hasD && hasP {
            out.append(.init(keys: ["TG0D", "TG0P"],
                             short: L.sensorGPUEdge,
                             label: L.sensorGPUEdgeLabel))
        }
        if hasD {
            out.append(.init(keys: ["TG0D"],
                             short: L.sensorGPUCore,
                             label: L.sensorGPUCoreLabel))
        } else if hasP {
            out.append(.init(keys: ["TG0P"],
                             short: L.sensorGPUCore,
                             label: L.sensorGPUCoreLabel))
        }
        if out.isEmpty {
            // 无驱动显卡（macOS 下的 NVIDIA）不会暴露 TG0x，保留占位让界面结构稳定
            out.append(.init(keys: ["TG0D"],
                             short: L.sensorGPUCore,
                             label: L.sensorGPUCoreLabel))
        }
        return out
    }

    /// 机器实际暴露的核心键，按序号排序（`TC10C` 要排在 `TC9C` 之后，不能按字符串排）。
    static func coreKeys(available: Set<String>) -> [String] {
        available.compactMap { k -> (Int, String)? in
            guard k.hasPrefix("TC"), k.hasSuffix("C") else { return nil }
            guard let n = Int(k.dropFirst(2).dropLast()) else { return nil }
            return (n, k)
        }
        .sorted { $0.0 < $1.0 }
        .map(\.1)
    }
}
