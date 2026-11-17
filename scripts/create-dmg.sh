#!/bin/zsh
# 用法: ./scripts/create-dmg.sh <NotchMusic.app 路径> <版本号> <输出 dmg 路径>
# 生成带背景、图标布局和 Applications 快捷方式的安装镜像

set -euo pipefail

if [[ $# -lt 3 ]]; then
    echo "用法: $0 <app 路径> <版本号> <输出 dmg 路径>"
    exit 1
fi

APP_PATH="$1"
VERSION="$2"
OUT_PATH="$3"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BG_DIR="$ROOT/scripts/dmg"
VOLNAME="NotchMusic $VERSION"
MOUNT=""
TMP_DMG="$(mktemp -u /tmp/notchmusic-dmg.XXXXXX).dmg"
STAGE="$(mktemp -d /tmp/notchmusic-stage.XXXXXX)"

cleanup() {
    if [[ -n "$MOUNT" && -d "$MOUNT" ]]; then
        hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
    fi
    rm -rf "$STAGE" "$TMP_DMG"
}
trap cleanup EXIT

[[ -d "$APP_PATH" ]] || { echo "错误: 找不到 $APP_PATH"; exit 1; }
[[ -f "$BG_DIR/background.png" ]] || { echo "错误: 缺少 $BG_DIR/background.png"; exit 1; }

rm -f "$OUT_PATH"

# 清掉同名卷，避免挂载点被加上 " 1" 后缀
for vol in /Volumes/"$VOLNAME"*(N); do
    hdiutil detach "$vol" -force >/dev/null 2>&1 || true
done

# ---------- 1. 准备卷内容 ----------
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# ---------- 2. 创建可写镜像并挂载 ----------
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" \
    -ov -format UDRW "$TMP_DMG" >/dev/null
MOUNT="$(hdiutil attach "$TMP_DMG" -nobrowse -noautoopen | tail -1 | awk -F'\t' '{print $NF}')"
[[ -d "$MOUNT" ]] || { echo "错误: 挂载失败"; exit 1; }

mkdir -p "$MOUNT/.background"
cp "$BG_DIR/background.png" "$MOUNT/.background/"
[[ -f "$BG_DIR/background@2x.png" ]] && cp "$BG_DIR/background@2x.png" "$MOUNT/.background/"
chflags hidden "$MOUNT/.background"

# ---------- 3. 写入 Finder 窗口布局 ----------
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set the bounds of container window to {200, 200, 860, 620}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set background picture of viewOptions to file ".background:background.png"
        set position of item "NotchMusic.app" of container window to {178, 168}
        set position of item "Applications" of container window to {482, 168}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT" >/dev/null

# ---------- 4. 压缩为只读镜像 ----------
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 \
    -o "$OUT_PATH" >/dev/null

echo "DMG 已生成: $OUT_PATH"
