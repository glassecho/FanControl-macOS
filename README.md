# FanControl

**macOS 下的主板风扇调速工具**（面向 Hackintosh）。

给主板 Super I/O 芯片 Nuvoton NCT679x 补上 SMC 写能力，让黑苹果也能按温度曲线调速 ——
安静 / 标准 / 性能 / 全速 / 手动 / 自定义曲线六种模式，外加只读的显卡监控。

<img src="preview/01-control-standard.png" width="640" alt="FanControl 控制页">

---

## 下载

👉 **[前往 Releases 下载最新版](https://github.com/qq543070364/FanControl-macOS/releases)**

| 文件 | 给谁用 |
|---|---|
| **`FanControl-1.2.0.dmg`** | **普通用户装这个** —— 双击即可 |
| `FanControl-1.2.0.pkg` | 同上，也可以用命令行装 |
| `FanControl-1.2.0-src.zip` | 想自己编译的人 |

> ⚠️ 本软件**没有 Apple 开发者签名**（作者没有证书），Gatekeeper 会拦。
> 右键点安装包 → **打开** → 再点一次「打开」即可；
> 或到「系统设置 → 隐私与安全性」拉到底点「仍要打开」。

---

## 界面

| 控制页 · 标准 | 控制页 · 手动 |
|---|---|
| <img src="preview/01-control-standard.png" width="380" alt="标准模式"> | <img src="preview/02-control-manual.png" width="380" alt="手动模式"> |

| 控制页 · 自定义曲线 | 说明面板 |
|---|---|
| <img src="preview/03-control-custom-curve.png" width="380" alt="自定义曲线"> | <img src="preview/04-help-panel.png" width="380" alt="说明面板"> |

---

## 适用条件

**三条硬门槛，缺一不可：**

| 条件 | 要求 |
|---|---|
| 系统 | **Hackintosh**（能改 OpenCore 的 `config.plist`）—— 真 Mac 不适用 |
| 主板 Super I/O | **Nuvoton NCT679x**：`NCT6790D`…`NCT6798D`、`NCT679BD`，或 `NCT6779D` |
| 架构 | **Intel**（kext 编译为 x86_64）—— Apple Silicon 不适用 |

macOS 13 / 14 / 15 / 26 均可。装完跑一次自检确认：

```sh
zsh /usr/local/sbin/fancontrol-check
```

---

## 组成

| 组件 | 语言 | 作用 |
|---|---|---|
| `app/` | Swift / SwiftUI | 图形界面。**不提权** |
| `helper/fanctl.c` | C | 特权辅助程序，**唯一**写 SMC 的入口 |
| `gpufand` | C | 温度 → 占空比守护进程，开机自启 |

> `gpufand` 与 `SMCSuperIO.kext` 来自 [gpufan](https://github.com/shohart/gpufan)
> （shohart，BSD 3-Clause），不在本仓库内。

---

## 安装

```sh
# 安装包
sudo installer -pkg FanControl-1.2.0.pkg -target /

# 或者从源码
zsh build.sh          # 需要 Xcode Command Line Tools
sudo zsh install.sh
```

**装完必须做两件事**（详见 [`移植说明.md`](移植说明.md)）：

1. 把 `/usr/local/share/fancontrol/SMCSuperIO.kext` 放进 `EFI/OC/Kexts`，
   替换同名文件，并在 `config.plist → Kernel → Add` 里注册 ——
   **它必须排在 `VirtualSMC.kext` 之后**（OpenCore 按顺序注入，依赖没就位的会被静默跳过）。
2. 确认水泵通道：`pump_channel` 默认是 `ch6`（作者本机布局），换机器必须核对。

---

## 构建

```sh
zsh build.sh            # x86_64 + arm64 通用二进制
zsh build.sh native     # 只编本机架构（快）
zsh make-pkg.sh         # 打成 .pkg + .dmg
```

预览界面（离屏渲染，不需要真的跑起来）：

```sh
swiftc -O -parse-as-library -target x86_64-apple-macos13.0 \
  -sdk "$(xcrun --show-sdk-path)" -o /tmp/render \
  app/Model.swift app/Views.swift render.swift \
  -framework SwiftUI -framework AppKit -framework Foundation
FANCTL_PATH="$PWD/helper/fanctl" /tmp/render preview
```

---

## 目录结构

```
app/            SwiftUI 源码（App / Model / Views）与 Info.plist、图标
helper/         fanctl.c（特权辅助程序）+ fancontrol-check（自检脚本）
tools/          图标生成工具（makeicon.swift）
build.sh        编译
make-pkg.sh     打包 pkg / dmg
install.sh      直接安装（等价于 pkg）
uninstall.sh    卸载
render.swift    离屏渲染预览工具
移植说明.md      面向用户的完整文档
LICENSE         BSD 3-Clause
NOTICE          第三方组件归属声明
THIRD-PARTY/    gpufan 的许可证原文
```

---

## 设计要点

- **权限隔离**：界面不提权，只有 `fanctl` 需要 root。
  `/etc/sudoers.d/fancontrol` 只授权 `fanctl` 的五个子命令
  （`duty` / `rpm` / `bios` / `conf` / `daemon`），删掉即撤销。
- **不碰内核**：守护进程只通过 SMC 键操作，不与 kext 直接耦合，
  因此能和其他风扇软件共存（谁最后写谁生效）。
- **水泵硬锁**：默认通道不参与调速，界面上明确标出。

---

## 已知限制

- 显卡风扇**只能看、不能调** —— 由显卡固件的 PowerPlay 表 + 驱动管理，
  macOS 没有对外开放的写入接口。要改只能在 OpenCore 里注入软 PowerPlay 表。
- 真 Mac、Apple Silicon 不适用。
- 没有 Apple 开发者签名（作者没有证书），Gatekeeper 会拦。

---

## 参与测试 / 反馈

这是**首次公开发布**，作者手上只有一台机器（ASUS 主板 + NCT679BD），
特别希望有**不同主板、不同芯片**的朋友帮忙一起测。

愿意帮忙的话，请到 [Issues](https://github.com/qq543070364/FanControl-macOS/issues) 反馈这几点：

1. 芯片型号 —— `ioreg -l -w0 | grep ChipName`
2. 自检结果 —— `zsh /usr/local/sbin/fancontrol-check`
3. 能不能调速（能不能拉到指定转速）
4. 水泵通道是几号，以及你是怎么判断的
5. 遇到的问题 —— 报错、崩溃、风扇异常行为，越具体越好

**已知的限制**（不用重复报）：

- 真 Mac、Apple Silicon 不适用
- 显卡风扇只能看、不能调
- 无驱动的显卡不显示显卡卡片
- 没有代码签名，需要手动放行

---

## 许可证

[BSD 3-Clause](LICENSE)。

包含第三方组件，归属声明见 [NOTICE](NOTICE) 与 [THIRD-PARTY/](THIRD-PARTY/)：

- [gpufan](https://github.com/shohart/gpufan) —— Copyright (c) 2026, shohart，BSD 3-Clause
- [VirtualSMC / SMCSuperIO](https://github.com/acidanthera/VirtualSMC) ——
  Copyright (c) 2018 vit9696 / joedm，BSD 3-Clause

本项目与上述上游项目的作者无关，也未获得其背书。特此感谢 shohart 与 VirtualSMC 团队的工作。

---

## 免责声明

本软件会修改主板风扇转速，并需要你修改 EFI。**任何对 EFI / OpenCore 配置的修改
都有导致无法开机的风险**，请务必先备份。本软件按「原样」提供，不提供任何担保，
使用造成的损失作者不承担责任。**不要把水冷泵纳入调速。**
