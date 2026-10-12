#!/bin/zsh
# FanControl 卸载脚本 —— 以 root 运行：
#   sudo zsh "/Users/mac/WorkBuddy AI/2026-10-08-18-53-57/FanControl/uninstall.sh"
#
# 会把所有风扇交还 BIOS，然后移除守护进程、辅助程序、sudoers 规则与应用。
set -e

if [ "$(id -u)" != "0" ]; then
  echo "请用 root 运行：sudo zsh \"$0\""
  exit 1
fi

echo "== 1) 把风扇交还 BIOS =="
# 先停守护进程，再把每个通道的 F<n>Md 置 0
/bin/launchctl bootout system/com.shohart.gpufand 2>/dev/null || true
sleep 1
if [ -x /usr/local/sbin/fanctl ]; then
  /usr/local/sbin/fanctl bios all || true
else
  echo "   （fanctl 已不在，跳过；重启后由 BIOS 接管）"
fi

echo "== 2) 卸载 LaunchDaemon =="
/bin/rm -f /Library/LaunchDaemons/com.shohart.gpufand.plist

echo "== 3) 删除二进制与配置 =="
/bin/rm -f /usr/local/sbin/fanctl /usr/local/sbin/gpufand /usr/local/sbin/fancontrol-check
/bin/rm -f /usr/local/etc/gpufand.conf /usr/local/etc/fancontrol.conf
/bin/rm -f /var/run/gpufand.json

echo "== 4) 删除 sudoers 规则 =="
/bin/rm -f /etc/sudoers.d/fancontrol

echo "== 5) 删除应用 =="
/bin/rm -rf /Applications/FanControl.app

echo
echo "卸载完成。风扇已交还 BIOS。"
echo
echo "注意：以下两处**保留**，需要时手动处理 ——"
echo "  · /usr/local/share/fancontrol/  （kext、默认配置、移植说明）"
echo "      不需要了： sudo rm -rf /usr/local/share/fancontrol"
echo "  · EFI 里的 SMCSuperIO.kext（支持 Nuvoton 写能力的那个）"
echo "      它本身无害，只是让 SMC 暴露 F<n>Tg 等可写键。"
echo "      想恢复原版：把 EFI/OC/Kexts 里 SMCSuperIO.kext.bak-* 换回去，重启即可。"
