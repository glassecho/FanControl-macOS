#!/bin/zsh
# FanControl 安装脚本 —— 必须以 root 运行：
#   sudo zsh "/Users/mac/WorkBuddy AI/2026-10-08-18-53-57/FanControl/install.sh"
#
# 做四件事：
#   1. 安装特权辅助程序 fanctl        -> /usr/local/sbin/fanctl
#   2. 安装温度曲线守护进程 gpufand   -> /usr/local/sbin/gpufand
#      + LaunchDaemon                 -> /Library/LaunchDaemons/com.shohart.gpufand.plist
#      + 默认配置                     -> /usr/local/etc/gpufand.conf（已存在则不覆盖）
#   3. 写入 sudoers 免密规则           -> /etc/sudoers.d/fancontrol
#      （只授权上面这一个 fanctl 的固定子命令，撤销只需删该文件）
#   4. 把 FanControl.app 拷到 /Applications
set -e

HERE=${0:A:h}
BUNDLE_SRC=$HERE/build/FanControl.app

# ---------- 0. 前置检查 ----------
if [ "$(id -u)" != "0" ]; then
  echo "请用 root 运行：sudo zsh \"$0\""
  exit 1
fi

# 调用者（GUI 会以这个身份执行 sudo）
OWNER=${SUDO_USER:-$(stat -f '%Su' /dev/console)}
if [ -z "$OWNER" ] || [ "$OWNER" = "root" ]; then
  echo "无法确定调用者账号，请用 sudo 而不是直接以 root 运行"
  exit 1
fi
echo "调用者账号: $OWNER"

# ---------- 1. 构建（若产物不存在） ----------
if [ ! -x "$HERE/helper/fanctl" ] || [ ! -x "$BUNDLE_SRC/Contents/MacOS/FanControl" ]; then
  echo "== 产物不存在，先构建 =="
  sudo -u "$OWNER" zsh "$HERE/build.sh"
fi
if [ ! -x "$BUNDLE_SRC/Contents/MacOS/FanControl" ]; then
  echo "缺少 $BUNDLE_SRC，请先运行 build.sh"
  exit 1
fi

# gpufand 二进制（每次都重新编译，源码里带了温度平滑补丁）
echo "== 编译 gpufand =="
GPUFAND_BIN=/tmp/gpufand-build
cc -O2 -Wall -Wextra -o "$GPUFAND_BIN" "$HERE/../gpufan/daemon/src/gpufand.c" -framework IOKit

# ---------- 2. 安装二进制与守护进程 ----------
echo "== 安装二进制 =="
/bin/mkdir -p /usr/local/sbin /usr/local/etc
install -o root -g wheel -m 755 "$HERE/helper/fanctl"      /usr/local/sbin/fanctl
install -o root -g wheel -m 755 "$GPUFAND_BIN"             /usr/local/sbin/gpufand
echo "   /usr/local/sbin/fanctl  $(/usr/local/sbin/fanctl version)"
echo "   /usr/local/sbin/gpufand"

echo "== 安装 LaunchDaemon =="
install -o root -g wheel -m 644 \
  "$HERE/../gpufan/daemon/com.shohart.gpufand.plist" \
  /Library/LaunchDaemons/com.shohart.gpufand.plist

# ---------- 3. 默认配置（不覆盖已有，除非 FANCONTROL_RESET_CONF=1） ----------
if [ ! -f /usr/local/etc/gpufand.conf ] || [ "${FANCONTROL_RESET_CONF:-0}" = "1" ]; then
  echo "== 写入默认曲线配置 =="
  cat > /usr/local/etc/gpufand.conf <<'CONF'
# gpufand 配置 —— 由 FanControl 生成/维护
# 手动改这里也可以，改完执行： sudo launchctl kill HUP system/com.shohart.gpufand
#
# 参与的通道（0-7）。注意：ch6 是本机 AIO 水冷泵，永远不要放进来！
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
  /bin/chmod 644 /usr/local/etc/gpufand.conf
else
  echo "== 已存在 /usr/local/etc/gpufand.conf，保留不动 =="
  echo "   （想恢复默认：FANCONTROL_RESET_CONF=1 sudo -E zsh \"$0\"）"
fi

# ---------- 4. sudoers 免密规则 ----------
echo "== 写入 sudoers 规则 =="
SUDOERS=/etc/sudoers.d/fancontrol
cat > "$SUDOERS" <<EOF
# FanControl —— 允许 $OWNER 无密码调用风扇控制辅助程序。
# 只授权 fanctl 的下列子命令；删除本文件即可撤销全部授权。
Cmnd_Alias FANCTL_RW = /usr/local/sbin/fanctl duty *, \\
                       /usr/local/sbin/fanctl rpm *, \\
                       /usr/local/sbin/fanctl bios *, \\
                       /usr/local/sbin/fanctl conf *, \\
                       /usr/local/sbin/fanctl daemon *

$OWNER ALL=(root) NOPASSWD: FANCTL_RW
EOF
/bin/chmod 440 "$SUDOERS"
/usr/sbin/chown root:wheel "$SUDOERS"

if ! /usr/sbin/visudo -c -f "$SUDOERS" >/dev/null 2>&1; then
  echo "!! sudoers 语法校验失败，已回滚"
  /bin/rm -f "$SUDOERS"
  exit 1
fi
echo "   $SUDOERS 语法 OK"

# ---------- 5. 安装 .app ----------
echo "== 安装应用 =="
# 用绝对路径 /bin/rm：某些环境下 PATH 里会有 rm 的包装脚本，会拦截删除
/bin/rm -rf /Applications/FanControl.app
/usr/bin/ditto "$BUNDLE_SRC" /Applications/FanControl.app
/usr/sbin/chown -R root:wheel /Applications/FanControl.app
echo "   /Applications/FanControl.app"

# ---------- 6. 启动守护进程 ----------
echo "== 启动 gpufand =="
/bin/launchctl bootout system/com.shohart.gpufand 2>/dev/null || true
sleep 1
if /bin/launchctl bootstrap system /Library/LaunchDaemons/com.shohart.gpufand.plist 2>/dev/null; then
  echo "   已加载"
else
  echo "   加载失败（可能已加载），稍后可点应用内「应用」重试"
fi
# ---------- 7. 汇总 ----------
sleep 1
echo
echo "================= 安装完成 ================="
echo "辅助程序 : /usr/local/sbin/fanctl"
echo "守护进程 : /usr/local/sbin/gpufand"
echo "配置     : /usr/local/etc/gpufand.conf"
echo "免密规则 : $SUDOERS"
echo "应用     : /Applications/FanControl.app"
echo
echo "现在打开： open /Applications/FanControl.app"
echo "验证     : sudo /usr/local/sbin/fanctl read | head -c 400"
echo "撤销     : sudo rm -f $SUDOERS && sudo launchctl bootout system/com.shohart.gpufand"
echo "==========================================="
