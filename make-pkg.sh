#!/bin/zsh
# 打包 FanControl 安装包（.pkg）
#
#   zsh make-pkg.sh
#
# 产物： build/pkg/FanControl-<版本>.pkg
#
# 说明：
#   · 未做 Apple 开发者签名（没有证书）。用户双击时可能需要
#     右键 → 打开，或用 sudo installer -pkg ... -target / 安装。
#   · postinstall 脚本会按"当前登录的图形账号"写 sudoers 免密规则。
set -e
HERE=${0:A:h}
VERSION=1.2.0
IDENT=local.hackintosh.fancontrol

PKGDIR=$HERE/build/pkg
PAYLOAD=$PKGDIR/payload
SCRIPTS=$PKGDIR/scripts
OUT=$HERE/build/pkg/FanControl-$VERSION.pkg
SHARE=/usr/local/share/fancontrol

APP=$HERE/build/FanControl.app
KEXT=$HERE/../gpufan/kext/build/SMCSuperIO.kext

echo "== 0) 前置检查 =="
if [ ! -d "$APP" ]; then
  echo "缺少 $APP，先运行 build.sh"; exit 1
fi
if [ ! -d "$KEXT" ]; then
  echo "缺少 $KEXT，先构建 gpufan 的 kext"; exit 1
fi
echo "   app  : $(lipo -archs "$APP/Contents/MacOS/FanControl")"
echo "   kext : $(lipo -archs "$KEXT/Contents/MacOS/SMCSuperIO")"

echo "== 1) 准备 payload =="
/bin/rm -rf "$PKGDIR"
/bin/mkdir -p \
  "$PAYLOAD/Applications" \
  "$PAYLOAD/Library/LaunchDaemons" \
  "$PAYLOAD/usr/local/sbin" \
  "$PAYLOAD$SHARE" \
  "$SCRIPTS"

/usr/bin/ditto "$APP"                                   "$PAYLOAD/Applications/FanControl.app"
/usr/bin/ditto "$HERE/helper/fanctl"                    "$PAYLOAD/usr/local/sbin/fanctl"
/usr/bin/ditto "$HERE/helper/fancontrol-check"          "$PAYLOAD/usr/local/sbin/fancontrol-check"
/usr/bin/ditto "$HERE/../gpufan/daemon/com.shohart.gpufand.plist" \
                                                        "$PAYLOAD/Library/LaunchDaemons/com.shohart.gpufand.plist"
/usr/bin/ditto "$KEXT"                                  "$PAYLOAD$SHARE/SMCSuperIO.kext"
/usr/bin/ditto "$HERE/移植说明.md"                       "$PAYLOAD$SHARE/移植说明.md"
/usr/bin/ditto "$HERE/uninstall.sh"                     "$PAYLOAD$SHARE/uninstall.sh"
# BSD 3-Clause 第 2 条：二进制分发必须附带版权声明与免责声明
/usr/bin/ditto "$HERE/LICENSE"                          "$PAYLOAD$SHARE/LICENSE"
/usr/bin/ditto "$HERE/NOTICE"                           "$PAYLOAD$SHARE/NOTICE"
/usr/bin/ditto "$HERE/THIRD-PARTY"                      "$PAYLOAD$SHARE/THIRD-PARTY"
/bin/chmod 755 "$PAYLOAD/usr/local/sbin/fanctl" \
               "$PAYLOAD/usr/local/sbin/fancontrol-check" \
               "$PAYLOAD$SHARE/uninstall.sh"

# gpufand 守护进程二进制
cc -O2 -Wall -Wextra -arch x86_64 -arch arm64 \
   -o "$PAYLOAD/usr/local/sbin/gpufand" \
   "$HERE/../gpufan/daemon/src/gpufand.c" -framework IOKit
/bin/chmod 755 "$PAYLOAD/usr/local/sbin/gpufand"

# 默认配置
cat > "$PAYLOAD$SHARE/gpufand.conf.default" <<'CONF'
# gpufand 配置 —— 由 FanControl 生成/维护
# 手动改这里也可以，改完执行： sudo launchctl kill HUP system/com.shohart.gpufand
#
# 参与的通道（0-7）。注意：不要把 AIO 水冷泵放进来！
# 本机（ASUS + NCT679BD）的泵是 ch6；换机器请先用 fancontrol-check 确认。
fans = 1,2,5

# 温度来源： 键[,键] : 温度:占空比 ...
# 多条 source 取"占空比最大"的那条；同一行多个键取"最热"的那个。
#
# CPU 用 8 个核心传感器（TC0C..TC7C）：它们平滑。
# 不要用 TC0P/TC0D —— 那是封装/晶片，会随睿频瞬时冲高（实测 33→65→35 来回跳），
# 直接拿来控速会让风扇几秒内反复拉高又降下来，很吵。
source = TC0C,TC1C,TC2C,TC3C,TC4C,TC5C,TC6C,TC7C : 42:22 58:38 72:65 84:100
source = TG0D,TG0P : 42:22 58:38 72:65 84:100

interval   = 2
min_duty   = 22
smooth     = 5
fail_duty  = 100
fail_limit = 3
down_step  = 2
hysteresis = 3
CONF

cat > "$PAYLOAD$SHARE/fancontrol.conf.default" <<'CONF'
# FanControl 本机参数
#
# 水泵通道。每台机器的风扇通道编号不同，默认按 6 处理（本机 ASUS + NCT679BD 的布局）。
#
# ★ 换机器后请先确认：泵的转速明显偏高且几乎恒定、不随 CPU 温度变化。
#   确认办法见「移植说明.md」第三节，或直接跑 fancontrol-check。
#
# 确认后取消下面这行的注释并填上正确通道号：
# pump_channel = 6
CONF

echo "== 2) 写安装脚本 =="

cat > "$SCRIPTS/preinstall" <<'PRE'
#!/bin/bash
# 安装前：停掉正在跑的守护进程和界面程序，避免文件被占用
echo "[FanControl] 停止旧版本..."
/bin/launchctl bootout system/com.shohart.gpufand 2>/dev/null || true
/usr/bin/pkill -f "/Applications/FanControl.app/Contents/MacOS/FanControl" 2>/dev/null || true
sleep 1
exit 0
PRE

cat > "$SCRIPTS/postinstall" <<'POST'
#!/bin/bash
# 安装后：建配置、写 sudoers 规则、加载守护进程
set +e
echo "[FanControl] 安装后配置..."

SHARE=/usr/local/share/fancontrol

# ---- 1. 配置文件（已存在则不覆盖，避免升级时丢失用户设置）----
/bin/mkdir -p /usr/local/etc
if [ ! -f /usr/local/etc/gpufand.conf ]; then
  /bin/cp "$SHARE/gpufand.conf.default" /usr/local/etc/gpufand.conf
  /bin/chmod 644 /usr/local/etc/gpufand.conf
  echo "  已写入默认 gpufand.conf"
else
  echo "  保留已有 gpufand.conf"
fi
if [ ! -f /usr/local/etc/fancontrol.conf ]; then
  /bin/cp "$SHARE/fancontrol.conf.default" /usr/local/etc/fancontrol.conf
  /bin/chmod 644 /usr/local/etc/fancontrol.conf
  echo "  已写入默认 fancontrol.conf（水泵通道待确认）"
else
  echo "  保留已有 fancontrol.conf"
fi

# ---- 2. sudoers 免密规则：按当前登录的图形账号写 ----
CONSOLE_USER=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null)
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ]; then
  RULE_SUBJECT="%admin"
  echo "  取不到图形登录账号，改用 %admin 组"
else
  RULE_SUBJECT="$CONSOLE_USER"
fi

SUDOERS=/etc/sudoers.d/fancontrol
cat > "$SUDOERS" <<EOF
# FanControl —— 允许 $RULE_SUBJECT 无密码调用风扇控制辅助程序。
# 只授权 fanctl 的下列子命令；删除本文件即可撤销全部授权。
Cmnd_Alias FANCTL_RW = /usr/local/sbin/fanctl duty *, \\
                       /usr/local/sbin/fanctl rpm *, \\
                       /usr/local/sbin/fanctl bios *, \\
                       /usr/local/sbin/fanctl conf *, \\
                       /usr/local/sbin/fanctl daemon *

$RULE_SUBJECT ALL=(root) NOPASSWD: FANCTL_RW
EOF
/bin/chmod 440 "$SUDOERS"
/usr/sbin/chown root:wheel "$SUDOERS"

if ! /usr/sbin/visudo -c -f "$SUDOERS" >/dev/null 2>&1; then
  echo "  !! sudoers 语法校验失败，已删除该文件（风扇将无法调速）"
  /bin/rm -f "$SUDOERS"
else
  echo "  sudoers 规则已写入（授权对象：$RULE_SUBJECT）"
fi

# ---- 3. 加载守护进程 ----
/bin/launchctl bootout system/com.shohart.gpufand 2>/dev/null || true
sleep 1
if /bin/launchctl bootstrap system /Library/LaunchDaemons/com.shohart.gpufand.plist 2>/dev/null; then
  echo "  gpufand 已启动"
else
  echo "  gpufand 启动失败（可稍后在应用里点「应用」重试）"
fi

# ---- 4. 标记 ----
/bin/mkdir -p /usr/local/var
echo "$(date '+%Y-%m-%d %H:%M:%S') installed" > /usr/local/var/fancontrol-installed

echo ""
echo "=========================================="
echo " FanControl 安装完成"
echo ""
echo " 下一步（换过机器的话，两件都必做）："
echo "   1. 把 $SHARE/SMCSuperIO.kext"
echo "      放进 EFI/OC/Kexts（替换同名文件），并在 config.plist"
echo "      的 Kernel -> Add 里注册 —— 详见 $SHARE/移植说明.md"
echo "   2. 运行自检确认水泵通道："
echo "        zsh /usr/local/sbin/fancontrol-check"
echo ""
echo " 然后打开 /Applications/FanControl.app"
echo "=========================================="
exit 0
POST

/bin/chmod 755 "$SCRIPTS/preinstall" "$SCRIPTS/postinstall"

echo "== 3) pkgbuild =="
/usr/bin/pkgbuild \
  --root "$PAYLOAD" \
  --scripts "$SCRIPTS" \
  --identifier "$IDENT" \
  --version "$VERSION" \
  --ownership recommended \
  --install-location / \
  "$PKGDIR/FanControl-component.pkg"

echo "== 4) 组装最终安装包 =="
/bin/mkdir -p "$PKGDIR/resources"
cat > "$PKGDIR/resources/welcome.html" <<'HTML'
<html><head><meta charset="utf-8"><style>
body{font:13px -apple-system,sans-serif;color:#ddd;background:transparent;margin:0}
h2{font-size:15px;margin:0 0 8px}
ul{margin:6px 0 0 18px;padding:0}li{margin:3px 0}
code{background:rgba(255,255,255,.1);padding:1px 4px;border-radius:3px}
.warn{color:#ffb340}
</style></head><body>
<h2>FanControl 1.2.0</h2>
<p>在 macOS 下控制主板风扇转速：安静 / 标准 / 性能 / 全速 / 手动 / 自定义曲线。</p>
<ul>
  <li>适用：<b>Intel Hackintosh</b> + 主板 Super I/O 为 <b>Nuvoton NCT679x</b></li>
  <li>本包会安装界面程序、特权辅助程序、温度曲线守护进程，并配置免密规则</li>
  <li>安装后会附带带 Nuvoton 写能力的 <code>SMCSuperIO.kext</code>，
      需要你手动放进 EFI/OC/Kexts 并重启</li>
  <li><b>本版新增</b>：显卡监控 —— 风扇转速 / 温度 / 功耗 / 核心与显存频率 / 占用率
      （<b>只读</b>；显卡风扇由显卡固件管理，本程序不参与显卡调速）</li>
  <li>许可证：BSD 3-Clause。含第三方组件声明，见包内 <code>LICENSE</code> 与 <code>NOTICE</code></li>
</ul>
<p class="warn">⚠ 换过机器的话，装完请务必运行
<code>zsh /usr/local/sbin/fancontrol-check</code> 确认水泵通道。</p>
</body></html>
HTML

cat > "$PKGDIR/resources/conclusion.html" <<'HTML'
<html><head><meta charset="utf-8"><style>
body{font:13px -apple-system,sans-serif;color:#ddd;background:transparent;margin:0}
code{background:rgba(255,255,255,.1);padding:1px 4px;border-radius:3px}
</style></head><body>
<p><b>安装完成。</b></p>
<p>接下来两件事：</p>
<ol>
  <li>把 <code>/usr/local/share/fancontrol/SMCSuperIO.kext</code> 放进
      EFI/OC/Kexts（替换同名文件）并在 config.plist 的 Kernel → Add 里注册，然后重启。
      <br>详细步骤见 <code>/usr/local/share/fancontrol/移植说明.md</code></li>
  <li>运行 <code>zsh /usr/local/sbin/fancontrol-check</code> 确认水泵通道。</li>
</ol>
<p>然后打开 <b>/Applications/FanControl.app</b>。</p>
</body></html>
HTML

cat > "$PKGDIR/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>FanControl</title>
    <organization>local.hackintosh</organization>
    <domains enable_localSystem="true" enable_anywhere="false" enable_currentUserHome="false"/>
    <options customize="never" require-scripts="true" hostArchitectures="x86_64,arm64"/>
    <allowed-os-versions>
        <os-version min="13.0"/>
    </allowed-os-versions>
    <welcome file="welcome.html" mime-type="text/html"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <choices-outline>
        <line choice="default"/>
    </choices-outline>
    <choice id="default" visible="false">
        <pkg-ref id="$IDENT"/>
    </choice>
    <pkg-ref id="$IDENT" version="$VERSION" onConclusion="none">FanControl-component.pkg</pkg-ref>
</installer-gui-script>
XML

/usr/bin/productbuild \
  --distribution "$PKGDIR/distribution.xml" \
  --resources "$PKGDIR/resources" \
  --package-path "$PKGDIR" \
  "$OUT"

echo "== 5) 验证 =="
/usr/sbin/pkgutil --check-signature "$OUT" 2>&1 | head -3 || true
ls -lh "$OUT"

echo "== 6) 打包成 DMG（方便拷到别的机器）=="
DMGROOT=$PKGDIR/dmg
/bin/rm -rf "$DMGROOT"
/bin/mkdir -p "$DMGROOT"
/usr/bin/ditto "$OUT" "$DMGROOT/FanControl-$VERSION.pkg"
/usr/bin/ditto "$HERE/移植说明.md" "$DMGROOT/移植说明.md"
/usr/bin/ditto "$HERE/LICENSE" "$DMGROOT/LICENSE"
/usr/bin/ditto "$HERE/NOTICE" "$DMGROOT/NOTICE"
/usr/bin/ditto "$HERE/THIRD-PARTY" "$DMGROOT/THIRD-PARTY"

cat > "$DMGROOT/先读我.txt" <<'TXT'
FanControl 1.2.0 —— 在 macOS 下控制主板风扇转速
=================================================

【这个包是给什么机器用的】

  ✓ Intel 的 Hackintosh（能改 OpenCore 的 config.plist）
  ✓ 主板 Super I/O 芯片是 Nuvoton NCT679x（NCT6790D…NCT6798D、NCT679BD）
  ✗ 真 Mac —— 装不了第三方 kext，本方案不适用
  ✗ Apple Silicon —— kext 是 x86_64 的，且 Apple Silicon 用不到这套

  不确定的话：装完运行
      zsh /usr/local/sbin/fancontrol-check
  它会逐项检查并给出结论。


【安装】

  双击 FanControl-1.2.0.pkg

  本包没有 Apple 开发者签名。如果提示"无法打开，因为来自身份不明的开发者"：
    · 右键点安装包 → 打开 → 再点"打开"，或
    · 系统设置 → 隐私与安全性 → 拉到底点"仍要打开"，或
    · 直接在终端里装：
        sudo installer -pkg FanControl-1.2.0.pkg -target /


【装完必须做的两件事】

  1) 把 /usr/local/share/fancontrol/SMCSuperIO.kext
     放进 EFI/OC/Kexts（替换同名文件），并在 config.plist 的
     Kernel → Add 里注册，然后重启。

     ⚠ 它必须排在 VirtualSMC.kext 之后 —— OpenCore 按顺序注入，
       依赖没就位的那一项会被静默跳过（不报错、日志里连尝试都没有）。

  2) 确认水泵通道（很重要，别跳过）
     每台机器的风扇通道编号不同，程序默认按 ch6 处理。
     确认办法：让机器空载静置，看哪个通道转速明显偏高且几乎恒定、
     不随 CPU 温度变化 —— 那就是泵。
     确认后：
        sudo sh -c 'echo pump_channel = <通道号> >> /usr/local/etc/fancontrol.conf'
        sudo launchctl kickstart -k system/com.shohart.gpufand

     ⚠ 不要把水泵纳入调速，泵速过低会导致冷液流量不足。


【详细说明】

  见同目录下的 移植说明.md
  （安装后也会有一份在 /usr/local/share/fancontrol/移植说明.md）


【关于开机自启】

  · 温度曲线守护进程 gpufand 是开机自启的 —— 你选的模式重启后会自动恢复。
  · 界面程序不自启，也不需要：调速由守护进程在做，界面只在改设置时打开。


【显卡监控（只读）】

  主界面下方的「显卡」卡片显示显卡的风扇转速、温度、功耗、
  核心频率、显存频率、占用率。

  ⚠ 显卡风扇只能看，不能调：
     · 它由显卡固件的 PowerPlay 表 + 显卡驱动共同管理，macOS 没有开放的写入接口
     · 要改它，只能在 OpenCore 的 DeviceProperties 里注入修改过的
       PP_PhmSoftPowerPlayTable（重启生效，只影响 macOS）
     · 无驱动的显卡（例如 macOS 下的 NVIDIA 30 系）不显示这张卡片

  查原始数据（只读，不需要 root）：
      /usr/local/sbin/fanctl gpu


【许可证】

  本程序以 BSD 3-Clause 许可证发布，见同目录 LICENSE。

  其中包含来自 gpufan（Copyright (c) 2026, shohart）的
  SMCSuperIO.kext 与 gpufand 守护进程，以及派生自
  VirtualSMC / SMCSuperIO（Copyright (c) 2018 vit9696 / joedm）的代码。
  完整第三方声明见同目录 NOTICE 与 THIRD-PARTY/。

  本项目与上述上游项目的作者无关，也未获得其背书。
TXT

/bin/rm -f "$HERE/build/pkg/FanControl-$VERSION.dmg"
/usr/bin/hdiutil create \
  -volname "FanControl $VERSION" \
  -srcfolder "$DMGROOT" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$HERE/build/pkg/FanControl-$VERSION.dmg" >/dev/null

echo "== 7) 产物 =="
ls -lh "$OUT" "$HERE/build/pkg/FanControl-$VERSION.dmg"
echo "OK: $HERE/build/pkg/FanControl-$VERSION.dmg"
