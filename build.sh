#!/bin/zsh
# 构建 FanControl：特权辅助程序 + SwiftUI 应用 + .app 包
#
# 默认产出 x86_64 + arm64 通用二进制（Intel 与 Apple Silicon 都能跑）。
# 若某个架构的 SDK 不可用，会自动退回只编译本机架构。
#
#   zsh build.sh            通用
#   zsh build.sh native     只编译本机架构（快）
set -e
HERE=${0:A:h}
APP=$HERE/app
HELPER=$HERE/helper
OUT=$HERE/build
BUNDLE=$OUT/FanControl.app
SDK=$(xcrun --show-sdk-path)
MODE=${1:-universal}

mkdir -p "$OUT"

can_build() {
  echo 'int main(void){return 0;}' > /tmp/.archtest.c
  cc -arch "$1" -o /tmp/.archtest /tmp/.archtest.c >/dev/null 2>&1
}

if [ "$MODE" = "native" ]; then
  ARCHS=($(uname -m))
else
  ARCHS=()
  can_build x86_64 && ARCHS+=(x86_64)
  can_build arm64  && ARCHS+=(arm64)
fi
echo "== 目标架构: ${ARCHS[*]} =="

ARCHFLAGS=()
for a in "${ARCHS[@]}"; do ARCHFLAGS+=(-arch "$a"); done

echo "== 1) 编译特权辅助程序 fanctl =="
cc -O2 -Wall -Wextra "${ARCHFLAGS[@]}" -o "$HELPER/fanctl" "$HELPER/fanctl.c" \
   -framework IOKit -framework CoreFoundation
echo "   -> $HELPER/fanctl  ($(lipo -archs "$HELPER/fanctl"))"

echo "== 2) 编译 SwiftUI 应用 =="
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

SLICES=()
for a in "${ARCHS[@]}"; do
  echo "   - $a"
  swiftc -O -parse-as-library \
    -target "$a-apple-macos13.0" \
    -sdk "$SDK" \
    -o "$OUT/FanControl-$a" \
    "$APP/App.swift" "$APP/Model.swift" "$APP/Views.swift" "$APP/StatusItem.swift" \
    -framework SwiftUI -framework AppKit -framework Foundation
  SLICES+=("$OUT/FanControl-$a")
done

if [ ${#SLICES[@]} -gt 1 ]; then
  lipo -create "${SLICES[@]}" -output "$BUNDLE/Contents/MacOS/FanControl"
  rm -f "${SLICES[@]}"
else
  mv "${SLICES[1]}" "$BUNDLE/Contents/MacOS/FanControl"
fi
echo "   -> $(lipo -archs "$BUNDLE/Contents/MacOS/FanControl")"

echo "== 3) 组装 .app =="
cp "$APP/Info.plist" "$BUNDLE/Contents/Info.plist"

# 图标：AppIcon.icns 由 tools/makeicon.swift + iconutil 生成（见 make-icon.sh）
if [ ! -f "$APP/AppIcon.icns" ]; then
  echo "   AppIcon.icns 不存在，先生成…"
  zsh "$HERE/make-icon.sh"
fi
cp "$APP/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"

cp "$HELPER/fanctl" "$BUNDLE/Contents/Resources/fanctl"
cp "$HELPER/fancontrol-check" "$BUNDLE/Contents/Resources/fancontrol-check"
chmod +x "$BUNDLE/Contents/Resources/fanctl" "$BUNDLE/Contents/Resources/fancontrol-check"
chmod +x "$BUNDLE/Contents/MacOS/FanControl"

# ad-hoc 签名，避免 Gatekeeper 抱怨
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || echo "   (codesign 跳过)"

echo "== 4) 验证 =="
plutil -lint "$BUNDLE/Contents/Info.plist"
file "$BUNDLE/Contents/MacOS/FanControl"
echo "OK: $BUNDLE"
