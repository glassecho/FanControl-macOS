import Foundation

// MARK: - 语言选择

/// 界面语言。**跟随系统**（macOS「语言与地区」里排第一的那个），
/// 不做界面上的手动开关 —— 少一个设置项、少一处 bug，也是 macOS 的标准做法。
///
/// 需要强制指定时，两个办法（都不用改代码）：
/// ```
/// # 1) 环境变量，优先级最高（适合离屏渲染、脚本调用）
/// FANCONTROL_LANG=en /Applications/FanControl.app/Contents/MacOS/FanControl
///
/// # 2) 偏好设置（适合长期改）
/// defaults write local.hackintosh.FanControl UILanguage en   # 强制英文
/// defaults write local.hackintosh.FanControl UILanguage zh   # 强制中文
/// defaults delete local.hackintosh.FanControl UILanguage     # 恢复跟随系统
/// ```
enum AppLang {
    case zh, en

    static let current: AppLang = {
        if let env = ProcessInfo.processInfo.environment["FANCONTROL_LANG"] {
            return env.lowercased().hasPrefix("en") ? .en : .zh
        }
        if let forced = UserDefaults.standard.string(forKey: "UILanguage") {
            return forced.lowercased().hasPrefix("en") ? .en : .zh
        }
        // 只要首选语言是中文系的（zh-Hans / zh-Hant / zh-HK…）就用中文，否则英文
        let best = Locale.preferredLanguages.first ?? "en"
        return best.lowercased().hasPrefix("zh") ? .zh : .en
    }()
}

// MARK: - 文案表

/// 全部界面文案。
///
/// **为什么不用 `NSLocalizedString` + `.lproj`？**
/// 本项目的 app 是 `swiftc` 直接编的（没有 Xcode 工程），String Catalog / `.strings`
/// 不会被自动处理，得自己往 bundle 里塞 `.lproj` 目录，还要操心 `.strings` 的编码。
/// 纯 Swift 表除了省掉这些，还多一个好处：**漏写就是编译错误**，
/// 不会等到用户切到英文才发现某处还是中文。
///
/// 写法上刻意把中英**并排放在同一行** —— 改文案时两边一起看见，不容易漏改一边。
struct LTable {
    let lang: AppLang
    private var zh: Bool { lang == .zh }

    // MARK: 应用 / 通用

    var appName: String { zh ? "风扇控制" : "FanControl" }
    var unknown: String { zh ? "未知" : "Unknown" }
    var dash: String { zh ? "—" : "—" }
    var reading: String { zh ? "读取中…" : "Reading…" }
    var ready: String { zh ? "就绪" : "Ready" }
    var okWord: String { zh ? "ok" : "ok" }
    var failedWord: String { zh ? "失败" : "failed" }

    // MARK: 控制模式

    var modeSilent: String { zh ? "安静" : "Silent" }
    var modeStandard: String { zh ? "标准" : "Standard" }
    var modePerformance: String { zh ? "性能" : "Performance" }
    var modeFull: String { zh ? "全速" : "Full speed" }
    var modeManual: String { zh ? "手动" : "Manual" }
    var modeCustom: String { zh ? "自定义曲线" : "Custom curve" }

    var modeSilentDetail: String { zh ? "最低 10%，85°C 才拉满" : "Floor 10%, maxes out at 85°C" }
    var modeStandardDetail: String { zh ? "平衡，日常默认" : "Balanced — the everyday default" }
    var modePerformanceDetail: String { zh ? "提前提速，压制温度" : "Ramps up early to hold temperatures down" }
    var modeFullDetail: String { zh ? "固定 100% 占空比" : "Fixed at 100% duty" }
    var modeManualDetail: String { zh ? "每个风扇一个固定占空比" : "A fixed duty per fan" }
    var modeCustomDetail: String { zh ? "自己拖动曲线控制点" : "Drag the curve control points yourself" }

    // MARK: 风扇状态

    var fanModeManualRPM: String { zh ? "手动·转速" : "Manual · RPM" }
    var fanModeManualDuty: String { zh ? "手动·占空比" : "Manual · duty" }
    var fanModeBIOS: String { zh ? "BIOS" : "BIOS" }

    var pumpLockedShort: String { zh ? "水泵 · 已锁定" : "Pump · locked" }
    var pumpLockedTip: String { zh ? "水泵通道，已锁定不参与调速" : "Pump channel — locked, never speed-controlled" }
    var fanSelectTip: String { zh ? "是否参与调速" : "Include this fan in speed control" }

    // MARK: 监控面板名 / 说明

    var panelCPU: String { zh ? "CPU" : "CPU" }
    var panelGPU: String { zh ? "显卡" : "GPU" }
    var panelMemory: String { zh ? "内存" : "Memory" }
    var panelStorage: String { zh ? "存储" : "Storage" }
    var panelNetwork: String { zh ? "网络" : "Network" }
    var panelProcesses: String { zh ? "进程" : "Processes" }
    var panelSensors: String { zh ? "传感器" : "Sensors" }
    var panelSystem: String { zh ? "系统" : "System" }

    var panelCPUDetail: String { zh ? "总占用 · 每个核心 · 负载" : "Total load · per core · load average" }
    var panelGPUDetail: String { zh ? "显卡风扇 · 温度 · 功耗" : "GPU fan · temperature · power" }
    var panelMemoryDetail: String { zh ? "已用 · 联动 · 压缩 · 交换" : "Used · wired · compressed · swap" }
    var panelStorageDetail: String { zh ? "各卷已用空间" : "Space used per volume" }
    var panelNetworkDetail: String { zh ? "上行 / 下行速率" : "Up / down throughput" }
    var panelProcessesDetail: String { zh ? "占用最高的进程" : "Top processes by CPU" }
    var panelSensorsDetail: String { zh ? "CPU / GPU 温度" : "CPU / GPU temperatures" }
    var panelSystemDetail: String { zh ? "机型 · 运行时间 · 负载" : "Model · uptime · load" }

    // MARK: 菜单栏可选项

    var mbIcon: String { zh ? "风扇图标" : "Fan icon" }
    var mbCPUTemp: String { zh ? "CPU 温度" : "CPU temp" }
    var mbGPUTemp: String { zh ? "GPU 温度" : "GPU temp" }
    var mbCPULoad: String { zh ? "CPU 占用" : "CPU load" }
    var mbMemory: String { zh ? "内存" : "Memory" }
    var mbFanRPM: String { zh ? "风扇转速" : "Fan RPM" }
    var mbGPUFan: String { zh ? "显卡风扇" : "GPU fan" }
    var mbNetwork: String { zh ? "网络" : "Network" }

    var mbIconDetail: String { zh ? "只显示一个图标" : "Just an icon" }
    var mbCPUTempDetail: String { zh ? "最热核心的温度" : "Hottest core temperature" }
    var mbGPUTempDetail: String { zh ? "显卡温度" : "GPU temperature" }
    var mbCPULoadDetail: String { zh ? "总占用率" : "Total CPU utilization" }
    var mbMemoryDetail: String { zh ? "已用比例" : "Used memory ratio" }
    var mbFanRPMDetail: String { zh ? "转得最快的受控风扇" : "Fastest controlled fan" }
    var mbGPUFanDetail: String { zh ? "显卡自身风扇转速" : "The GPU's own fan speed" }
    var mbNetworkDetail: String { zh ? "下行速率" : "Download throughput" }

    // MARK: 温度来源

    var sensorCPU8Cores: String { zh ? "8 核心" : "8 cores" }
    var sensorCPU8CoresLabel: String {
        zh ? "CPU 8 个核心，取最热 —— 平滑，推荐" : "CPU's 8 cores, hottest wins — smooth, recommended"
    }
    var sensorCPUPackage: String { zh ? "封装" : "Package" }
    var sensorCPUPackageLabel: String {
        zh ? "CPU 封装 (TC0P) —— 反应快但抖动大，容易让风扇忽高忽低"
           : "CPU package (TC0P) — responsive but jumpy; fans will surge and drop"
    }
    var sensorGPUEdge: String { zh ? "核心+板边" : "Core + edge" }
    var sensorGPUEdgeLabel: String { zh ? "GPU 核心与板边，取最热" : "GPU core and board edge, hottest wins" }
    var sensorGPUCore: String { zh ? "核心" : "Core" }
    var sensorGPUCoreLabel: String { zh ? "GPU 核心 (TG0D)" : "GPU core (TG0D)" }

    var gpuCoreSensor: String { zh ? "GPU 核心" : "GPU core" }
    var gpuEdgeSensor: String { zh ? "GPU 板边" : "GPU edge" }

    // MARK: 控制页

    var tabControl: String { zh ? "控制" : "Control" }
    var tabMonitor: String { zh ? "监控" : "Monitor" }

    var controlModeSection: String { zh ? "控制模式" : "Control mode" }
    var tempSourceSection: String { zh ? "温度来源" : "Temperature source" }
    var tempSourceHint: String {
        zh ? "同时勾选时，取两者中较热的那个；每条来源内部也取最热"
           : "When both are checked, the hotter one wins — and each source takes its own hottest"
    }
    var panelSection: String { zh ? "显示面板" : "Panels" }
    var showAll: String { zh ? "全部显示" : "Show all" }
    var hideAll: String { zh ? "全部隐藏" : "Hide all" }
    var panelSectionHint: String {
        zh ? "开关会记住，下次打开保持原样。监控页刷新间隔 2 秒。"
           : "Your choices are remembered. The monitor page refreshes every 2 seconds."
    }

    var dutyCurveSection: String { zh ? "温度 → 占空比 曲线" : "Temperature → duty curve" }
    var manualDutySection: String { zh ? "手动占空比" : "Manual duty" }
    var curveEditableHint: String { zh ? "拖动圆点调整，下方按钮增删" : "Drag the dots; add or remove below" }
    var curvePresetHint: String { zh ? "预设曲线（切换到自定义可编辑）" : "Preset curve — switch to Custom to edit" }
    var minDuty: String { zh ? "最低占空比" : "Minimum duty" }
    var minDutyWarn: String { zh ? "过低时部分风扇可能停转，留意下面转速" : "Too low and some fans may stall — watch the RPM below" }
    var minDutyHint: String { zh ? "曲线端点之外，占空比不会低于此值" : "Duty never drops below this outside the curve's endpoints" }
    var addPoint: String { zh ? "添加控制点" : "Add point" }
    var removePoint: String { zh ? "删除控制点" : "Remove point" }
    var manualHint: String {
        zh ? "手动模式下，下面每个风扇的滑块直接设定固定占空比；不会跟随温度变化。"
           : "In manual mode each fan's slider sets a fixed duty directly — it won't follow temperature."
    }
    var fanChannelSection: String { zh ? "风扇通道" : "Fan channels" }
    var fanChannelHint: String { zh ? "水泵通道已锁定 · 每 2 秒刷新" : "Pump channel locked · refreshes every 2s" }

    var overviewSection: String { zh ? "运行概览" : "Overview" }
    var overviewMore: String { zh ? "完整数据见左栏「监控」页" : "Full details on the Monitor page" }
    /// 英文刻意用短词：这个字符串会出现在「运行概览」的窄标签里，
    /// "System disk" 会折成两行，把那一行撑高。
    var systemDisk: String { zh ? "系统盘" : "Disk" }

    // MARK: 监控页

    var headerApply: String { zh ? "应用" : "Apply" }
    var headerApplying: String { zh ? "应用中…" : "Applying…" }
    var headerReturnBIOS: String { zh ? "交还 BIOS" : "Hand back to BIOS" }
    var headerHelpTip: String { zh ? "使用说明" : "Help" }
    var headerReading: String { zh ? "正在读取系统信息…（首次采样需要约 0.5 秒）" : "Reading system info… (the first sample takes about 0.5s)" }

    var labelThreads: String { zh ? "线程" : "threads" }
    var labelLoad: String { zh ? "负载" : "Load" }
    var labelPerCore: String { zh ? "每个核心" : "Per core" }
    var labelWired: String { zh ? "联动" : "Wired" }
    var labelCompressed: String { zh ? "压缩" : "Compressed" }
    var labelSwap: String { zh ? "交换" : "Swap" }
    var labelNoVolumes: String { zh ? "没有可显示的卷" : "No volumes to show" }
    var labelDown: String { zh ? "下行" : "Down" }
    var labelUp: String { zh ? "上行" : "Up" }
    var labelNetSampling: String { zh ? "正在采样…（首次需要两次读数）" : "Sampling… (needs two readings the first time)" }
    var labelNetHint: String { zh ? "速率按轮询间隔（约 2 秒）计算" : "Rate computed over the polling interval (~2s)" }
    var labelByCPU: String { zh ? "按 CPU 占用" : "By CPU usage" }
    var labelFromSMC: String { zh ? "来自 SMC" : "From SMC" }
    var labelNoSensors: String { zh ? "没有读到温度传感器" : "No temperature sensors found" }
    var labelUnknownCPU: String { zh ? "未知处理器" : "Unknown CPU" }
    var labelLogicalCores: String { zh ? "逻辑核心" : "Logical cores" }
    var labelUptime: String { zh ? "运行时间" : "Uptime" }
    var labelGPUFan: String { zh ? "风扇" : "Fan" }
    var labelTemp: String { zh ? "温度" : "Temp" }
    var labelPower: String { zh ? "功耗" : "Power" }
    var labelCoreClock: String { zh ? "核心频率" : "Core clock" }
    var labelMemClock: String { zh ? "显存频率" : "Memory clock" }
    var labelUtilization: String { zh ? "占用率" : "Utilization" }
    var labelReadOnlyMonitor: String { zh ? "只读监控" : "Read-only" }
    var labelService: String { zh ? "后台服务" : "Background service" }

    var gpuNote: String {
        zh ? "显卡风扇由显卡固件的 PowerPlay 表与驱动管理，macOS 没有开放的写入接口 —— "
           + "所以显卡风扇只能看、不能调。要改它得在 OpenCore 里注入修改过的风扇曲线，重启生效。"
           : "GPU fans are managed by the card's firmware PowerPlay table and its driver, and macOS exposes "
           + "no writable interface — so they can be read but never controlled. Changing them means injecting "
           + "a modified fan curve through OpenCore and rebooting."
    }

    // MARK: 菜单栏弹出面板

    var menuBarSection: String { zh ? "菜单栏显示" : "Menu bar" }
    var menuBarEmptyHint: String {
        zh ? "关掉全部也会保留一个图标 —— 不然菜单栏就点不到了。"
           : "Turning everything off still leaves an icon — otherwise the menu bar item would be unclickable."
    }
    var launchAtLogin: String { zh ? "开机自启" : "Launch at login" }
    var launchAtLoginHint: String {
        zh ? "开机后会自动打开主窗口，关掉即可 —— 菜单栏图标会一直留着。"
           : "Opens the main window at login; close it and the menu bar icon stays."
    }
    var openMainWindow: String { zh ? "打开主窗口" : "Open main window" }
    var refreshTip: String { zh ? "立即刷新" : "Refresh now" }
    var quitTip: String { zh ? "退出风扇控制" : "Quit FanControl" }
    var quitLabel: String { zh ? "退出" : "Quit" }
    var statLoad: String { zh ? "占用" : "Load" }
    var statMemory: String { zh ? "内存" : "Memory" }
    var statFan: String { zh ? "风扇" : "Fan" }
    var statGPU: String { zh ? "显卡" : "GPU" }

    // MARK: 状态文案

    var statusAutoRunning: String { zh ? "自动调速运行中" : "Auto control running" }
    var statusManual: String { zh ? "手动" : "Manual" }
    var statusBIOS: String { zh ? "BIOS 控制" : "BIOS control" }
    var svcUnknown: String { zh ? "未知" : "Unknown" }
    var svcNotInstalled: String { zh ? "未安装" : "Not installed" }
    var svcRunning: String { zh ? "运行中" : "Running" }
    var svcInstalledNotRunning: String { zh ? "已安装 · 未运行" : "Installed · not running" }

    var msgReadFailed: String { zh ? "读取状态失败" : "Failed to read status" }
    var msgNeedFan: String { zh ? "请至少勾选一个风扇" : "Select at least one fan" }
    var msgNeedTempSource: String { zh ? "请至少勾选一个温度来源" : "Select at least one temperature source" }
    var msgNeedInstall: String { zh ? "提示：需要先安装辅助程序（见安装脚本）" : "Note: the helper must be installed first (see the install script)" }
    var msgReturnedBIOS: String { zh ? "已交还 BIOS 控制" : "Handed back to BIOS control" }
    var msgLaunchOn: String {
        zh ? "已设为开机自启 —— 开机后会自动打开主窗口，关掉即可，菜单栏图标会保留"
           : "Launch at login enabled — the main window opens at login; close it and the menu bar icon stays"
    }
    var msgLaunchOff: String { zh ? "已关闭开机自启" : "Launch at login disabled" }
    var footerHint: String {
        zh ? "曲线由 gpufand 后台服务执行 · 重启后自动恢复"
           : "The curve is run by the gpufand background service · restored automatically after a reboot"
    }

    // MARK: 说明卡

    var helpTitle: String { zh ? "说明" : "Help" }
    var helpControl1: String {
        zh ? "「应用」把当前模式写入后台服务 gpufand，之后即使关掉本窗口也持续生效。"
           : "“Apply” writes the current mode into the gpufand background service, so it keeps working even after you close this window."
    }
    var helpControl2: String {
        zh ? "「交还 BIOS」停止后台服务，所有风扇交回主板 SmartFan 曲线。"
           : "“Hand back to BIOS” stops the background service and returns every fan to the motherboard's SmartFan curve."
    }
    var helpControl3: String {
        zh ? "手动模式会先停掉后台服务，再用每个风扇的滑块直接设定固定占空比。"
           : "Manual mode stops the background service first, then each fan's slider sets a fixed duty directly."
    }
    var helpMonitor: String {
        zh ? "左栏顶部的「控制 / 监控」切页。监控页里的面板可以逐个开关，"
           + "开关记在系统偏好里，下次打开保持原样。"
           : "Switch pages with “Control / Monitor” at the top of the left column. Monitor panels can be "
           + "toggled individually, and your choices are remembered."
    }
    var helpGPU: String {
        zh ? "「显卡」面板是只读的：显卡风扇由显卡固件的 PowerPlay 表与驱动管理，"
           + "macOS 没有开放写入接口，本程序不参与显卡调速。无驱动的显卡"
           + "（如 macOS 下的 NVIDIA 30 系）不会出现这个面板。"
           : "The GPU panel is read-only: GPU fans are managed by the card's firmware PowerPlay table and "
           + "its driver, macOS exposes no writable interface, and this app never touches GPU fan speed. "
           + "Cards without a driver (such as NVIDIA 30-series under macOS) don't show this panel at all."
    }
    var helpReadOnly: String {
        zh ? "CPU 占用、每核占用、内存、磁盘、网络、进程都来自只读采样，"
           + "不写任何东西、也不需要额外权限。"
           : "CPU usage, per-core usage, memory, disks, network and processes all come from read-only "
           + "sampling — nothing is written and no extra privileges are needed."
    }
    var helpSudo: String {
        zh ? "写 SMC 需要特权，安装脚本已为 fanctl 配置免密规则；撤销见 install.sh 末尾。"
           : "Writing to SMC needs privileges; the install script sets up a passwordless rule for fanctl. "
           + "See the end of install.sh to revoke it."
    }
    var helpCredits: String {
        zh ? "主板风扇的 SMC 键来自 gpufan 的 SMCSuperIO 补丁（BSD 3-Clause），见 NOTICE。"
           : "The motherboard fan SMC keys come from gpufan's SMCSuperIO patch (BSD 3-Clause); see NOTICE."
    }

    // MARK: 带变量的句子

    /// 警告：`ch` 与 `n` 在两边的语序不同，所以必须是函数，不能拼字符串。
    func pumpUnconfirmed(_ ch: Int) -> String {
        zh ? "水泵通道用的是默认值 ch\(ch)，未从配置读到 —— 换过机器请核对后再调速，确认办法见「?」里的说明。"
           : "The pump channel is using the built-in default (ch\(ch)) rather than the configured value — "
           + "if you've changed hardware, verify it before controlling fans. See the “?” panel for how."
    }
    func helpPump(_ ch: Int) -> String {
        zh ? "水冷泵（ch\(ch)）被锁定，不参与调速 —— 泵速过低会导致冷液流量不足。"
           + "通道号记在 /usr/local/etc/fancontrol.conf 的 pump_channel。"
           : "The pump (ch\(ch)) is locked and never speed-controlled — too low a pump speed starves the loop "
           + "of coolant flow. The channel number lives in pump_channel in /usr/local/etc/fancontrol.conf."
    }
    func core(_ n: Int) -> String { zh ? "核心 \(n)" : "Core \(n)" }
    func coreTooltip(_ n: Int, _ pct: Double) -> String {
        zh ? String(format: "核心 %d：%.0f%%", n, pct) : String(format: "Core %d: %.0f%%", n, pct)
    }
    func threads(_ n: Int) -> String { zh ? "\(n) 线程" : "\(n) threads" }
    func volumes(_ n: Int) -> String { zh ? "\(n) 个卷" : (n == 1 ? "1 volume" : "\(n) volumes") }
    func userPct(_ v: Double) -> String { zh ? String(format: "用户 %.1f%%", v) : String(format: "User %.1f%%", v) }
    func systemPct(_ v: Double) -> String { zh ? String(format: "系统 %.1f%%", v) : String(format: "System %.1f%%", v) }
    func hideTip(_ t: String) -> String { zh ? "点击隐藏「\(t)」" : "Click to hide “\(t)”" }
    func showTip(_ t: String) -> String { zh ? "点击显示「\(t)」" : "Click to show “\(t)”" }
    func backgroundService(_ s: String) -> String { zh ? "后台服务 \(s)" : "Background service \(s)" }
    func autoWith(_ m: String) -> String { zh ? "自动 · \(m)" : "Auto · \(m)" }
    func applied(_ m: String) -> String { zh ? "已应用：\(m)" : "Applied: \(m)" }
    func appliedWith(_ m: String, _ t: String) -> String { zh ? "已应用：\(m) · \(t)" : "Applied: \(m) · \(t)" }
    func returnFailed(_ e: String) -> String { zh ? "交还失败：\(e)" : "Hand back failed: \(e)" }
    func launchFailed(_ e: String) -> String { zh ? "设置开机自启失败：\(e)" : "Could not set launch at login: \(e)" }
    func cannotRun(_ exe: String, _ e: String) -> String { zh ? "无法执行 \(exe): \(e)" : "Cannot run \(exe): \(e)" }
    func logOK(_ ch: Int, _ d: Int) -> String { zh ? "ch\(ch) -> \(d)% ok" : "ch\(ch) -> \(d)% ok" }
    func logFail(_ ch: Int, _ d: Int) -> String { zh ? "ch\(ch) -> \(d)% 失败" : "ch\(ch) -> \(d)% failed" }
    func gpuFanExtra(_ rpm: Double) -> String { zh ? String(format: "· %.0f RPM", rpm) : String(format: "· %.0f RPM", rpm) }

    /// 秒 → 「3.4 小时」/「3.4 hours」。格式串本身两边就不一样，所以是三个函数。
    func days(_ v: Double) -> String { zh ? String(format: "%.1f 天", v) : String(format: "%.1f days", v) }
    func hours(_ v: Double) -> String { zh ? String(format: "%.1f 小时", v) : String(format: "%.1f hours", v) }
    func minutes(_ v: Double) -> String { zh ? String(format: "%.0f 分钟", v) : String(format: "%.0f min", v) }
}

/// 全局文案表。所有界面文字都从这里取 —— `Text(L.appName)`。
let L = LTable(lang: AppLang.current)
