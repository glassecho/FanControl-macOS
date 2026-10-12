#!/bin/zsh
# 生成 AppIcon.icns
#
#   zsh make-icon.sh
#
# 源图：app/AppIcon-source.png（方形 PNG，可带透明）
# 产物：app/AppIcon.icns（build.sh 会把它拷进 .app/Contents/Resources/）
#
# 做的是「缩放 + 居中留白」—— 源图如果内容贴满画布，直接当图标用会显得
# 比旁边的 App 大一圈。留白比例在 tools/makeicon.swift 里的 SCALE 调。
set -e
HERE=${0:A:h}
SRC=$HERE/app/AppIcon-source.png
ICONSET=$HERE/build/AppIcon.iconset
OUT=$HERE/app/AppIcon.icns

[ -f "$SRC" ] || { echo "缺少源图: $SRC"; exit 1; }

/bin/mkdir -p "$HERE/build"
/bin/rm -rf "$ICONSET"

echo "== 编译图标生成工具 =="
swiftc -O -o "$HERE/build/makeicon" "$HERE/tools/makeicon.swift"

echo "== 生成各尺寸 =="
"$HERE/build/makeicon" "$SRC" "$ICONSET"

echo "== 合成 icns =="
iconutil -c icns "$ICONSET" -o "$OUT"
ls -lh "$OUT"
echo "OK: $OUT"
