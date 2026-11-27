# FanControl 1.6.0

**macOS 下的主板风扇调速工具**（面向 Hackintosh）。给主板 Super I/O 芯片 Nuvoton NCT679x
补上 SMC 写能力，让黑苹果也能按温度曲线调速。

> **English?** [Jump to the English section ↓](#english)

**这一版解决的是「显存被别的程序吃干时，本 app 跟着崩」**，另外补掉了一个绘图路径上
早就在的 NaN 隐患。同时把此前从未发布过的 1.5.2 一并带上。

---

## 为什么要做这个

在一台 16 GB 显存的机器上，Lightroom Classic 的 AI 降噪跑完之后，显存占用是这样的：

| 项目 | 值 |
|---|---|
| 活跃占用 `inUseVidMemoryBytes` | 12.84 GB |
| 孤儿未回收 `orphanedReusable`（1783 块） | 2.95 GB |
| 剩余可用 `vramFreeBytes` | **159.8 MB** |
| 同一时刻 GPU 活动 / 核心频率 | **0% / 5 MHz** |

显卡完全空闲，显存却被占到 98.7%。这不是算力打满，是**占着不还**。

macOS 没有 Windows WDDM 那层显存虚拟化 —— 一个程序把显存吃满，别的程序一申请就失败。
于是接下来 20 分钟里，这台机器上连着崩了十几个互不相干的进程：

- **本 app 崩 3 次**，全部在主线程 SwiftUI 渲染
- WorkBuddy（Electron）1 次、`MTLCompilerService` 6 次（一分钟内连崩）
- `WindowServer` 主线程卡死 80 秒被 watchdog 强杀 2 次，11-26 那次升级成内核 panic、整机重启

退出 Lightroom 后显存立刻回到 8.1%（剩余 14.7 GB）。**根因在 Lightroom 那头**，
本 app 只是恰好站在显存分配的第一线：它每 2 秒把 8 块面板连图表全量重绘一遍，
每一步都要向 GPU 申请绘制表面。

所以这一版不做「根治」（app 也管不了别的程序的显存），只做**不跟着一起死**。

## 改了什么

### 1. 显存监控与自动降级（新增）

- 每 15 秒读一次 `ioreg -r -c IOAccelerator`，侧栏与 GPU 面板显示剩余显存和占用率
- 剩余 **< 1 GB** 进入降级态，**> 2 GB** 退出（留 1 GB 回差，避免在边界反复抖动）
- 降级期间：
  - CPU 走势图**不再建 Canvas**，换成静态占位块「已暂停」
  - 轮询间隔自动拉到不低于 8 秒
  - 顶部出现橙色横幅，写明剩余显存与占用率，带「立即刷新」按钮

解析上有个坑值得记一笔：`ioreg` 输出里 `vramFreeBytes` **排在** `inUseVidMemoryBytes`
**之后**，同一节点的统计还会重复输出两遍。按出现顺序配对必然错位（会把占用算成 0）。
正确做法是按 `\n+-o ` 切节点块、块内各取首值；多加速器时取总容量最大那块，
也就是 Lightroom / 游戏真正在用的独显 —— 取「剩余最少」的话，核显那点显存会天天误报。

### 2. NaN / ∞ 防护（修 bug）

`Sparkline` 原来只挡了 `count > 1` 和除零。但 Swift 的 `max/min` 遇 NaN 会把 NaN
**原样返回**，`min(max(v, 0), top)` 挡不住它，NaN 最终进了 `Path` 的坐标 ——
CoreGraphics 拿到 NaN 是未定义行为，这是崩溃的经典入口。

现在数据源和绘制端各自过滤一遍：`cpuHistory` 入库前夹值，`Sparkline`、`PlotGeom.px/py`、
`FlexBar` 各自再挡一次，谁都不依赖对方守规矩。顺带 `PlotGeom.py` 把占空比夹到 0…100
（原来异常值会画出画布外）。

### 3. 刷新间隔可调（新增）

- 1 / 2 / 3 / 5 / 10 秒，存 `fancontrol.pollInterval`
- 默认从写死的 **2 秒改为 3 秒**
- 定时器加了 `tolerance`，让系统把唤醒攒一起发

### 4. 首次运行默认只开 4 个面板

CPU / GPU / 传感器 / 内存，不再 8 个全开。每块面板都是一整套 SwiftUI 图层，
全开等于渲染面积拉满。已存过偏好的用户不受影响，侧栏「全部显示 / 全部隐藏」照旧。

### 5. 一并带来的 1.5.2（此前未发布）

- **版本号在界面上可见**：主窗口底栏、菜单栏面板标题旁、「?」说明卡底部；
  悬停显示带构建号的完整版本
- **温度来源候选按机器实际暴露的传感器生成**：原来写死 `TC0C…TC7C` 八个键、
  按钮上固定写「8 核心」，换台核心数不是 8 的机器就会带上不存在的键、标签也是错的

## 怎么升级

附件里的 `FanControl-1.6.0.pkg` 或 `FanControl-1.6.0.dmg` 都可以，装完重启 app 即可。
`gpufand` 守护进程、`fanctl` 辅助程序和 sudoers 规则均由安装包维护，**升级不需要重新配置**。

想亲眼看到降级是什么样（正常情况下走不到）：

```sh
open -n --env FANCONTROL_VRAM_LOW_MB=999999 /Applications/FanControl.app
```

会立刻判定「显存告急」：橙色横幅、走势图变占位块、轮询降到 8 秒。
关掉再正常打开就恢复，环境变量不会残留。

## 还是要说清楚的

macOS 没有「给某个程序分配多少显存」这种机制，这一版也做不到替别的程序留额度。
真正的源头仍是占用显存的那一方 —— 在本例中是 Lightroom：

- 一批 AI 降噪做完就重启一次 Lightroom，显存立刻全部归还（最省事）
- 想彻底避开：Lightroom 偏好设置 → 性能 → 自定义 → 取消「使用 GPU 进行图像处理」
  （代价是调色与 AI 降噪改走 CPU）

现在多了显存读数，反而多了一个观察窗口：侧栏那行「显存 XXXXX MB · XX%」，
掉到 1 GB 附近就知道该重启 Lightroom 了。

---

## English

**FanControl 1.6.0** — motherboard fan control for macOS (Hackintosh, Nuvoton NCT679x).

This release makes the app survive when another process has eaten all the VRAM.
On the machine that reported this, Lightroom Classic's AI denoise left 159 MB free out of
16 GB while the GPU was completely idle (0% activity, 5 MHz) — occupied, not busy.
macOS has no WDDM-style VRAM virtualization, so every other process that asked for a
surface failed to allocate: this app crashed three times in SwiftUI rendering, WindowServer
was killed by the watchdog twice, and one of those escalated to a kernel panic.

**Changes**

- **VRAM monitoring with automatic degradation.** Polls `ioreg` every 15 s, shows free VRAM
  and usage in the sidebar and GPU panel. Below **1 GB free** the app degrades (back above
  2 GB, 1 GB hysteresis): no `Canvas` for the CPU sparkline, polling stretched to ≥8 s, and
  an orange banner at the top of the monitor page.
- **NaN/∞ guards on the drawing path.** Swift's `max`/`min` propagate NaN, so a NaN could
  reach a `Path` coordinate — undefined behaviour in CoreGraphics and a classic crash entry.
  Filtered at both the data source and the drawing end.
- **Configurable refresh interval** (1/2/3/5/10 s, default 3 s, was hard-coded 2 s).
- **First run opens 4 panels instead of 8** (CPU / GPU / sensors / memory).
- Includes the previously unreleased 1.5.2: visible version number in three places, and
  temperature-source candidates generated from the sensors the machine actually exposes.

**Not fixed, and cannot be fixed here:** macOS has no per-process VRAM quota. The real
source is whichever app holds the memory — restart Lightroom after a batch of AI denoise,
or disable "Use GPU for image processing" in its Performance preferences.

---

**构建**：`swiftc` 直接编译，无 Xcode 工程；x86_64 薄二进制，ad-hoc 签名。
**校验**：`shasum -a 256 FanControl-1.6.0.pkg`
