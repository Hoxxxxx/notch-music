#!/bin/zsh
# NotchMusic 发布脚本：构建 Release -> 打包 DMG -> Sparkle 签名 -> 更新 appcast.xml -> 创建 GitHub Release
#
# 用法: ./scripts/release.sh <版本号> [更新说明]
# 示例: ./scripts/release.sh 0.3.0 "新增自动更新功能"
#
# 前置条件:
#   - 本机已用 Sparkle generate_keys 生成 EdDSA 密钥（存在钥匙串中）
#   - 已安装 gh（GitHub CLI）并登录

set -euo pipefail

SPARKLE_BIN_DIR="${SPARKLE_BIN_DIR:-/tmp/sparkle-tools/bin}"
REPO="Hoxxxxx/notch-music"

if [[ $# -lt 1 ]]; then
    echo "用法: $0 <版本号> [更新说明]"
    exit 1
fi

VERSION="$1"
NOTES="${2:-NotchMusic $VERSION}"
TAG="v$VERSION"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="$ROOT/NotchMusic.xcodeproj/project.pbxproj"
APPCAST="$ROOT/appcast.xml"
BUILD_DIR="$ROOT/build/release"
DMG_DIR="$ROOT/dist"
DMG_NAME="NotchMusic-$VERSION.dmg"
DMG_PATH="$DMG_DIR/$DMG_NAME"

if [[ ! -x "$SPARKLE_BIN_DIR/sign_update" ]]; then
    echo "错误: 未找到 sign_update 工具 ($SPARKLE_BIN_DIR/sign_update)"
    echo "请下载 Sparkle 工具并设置 SPARKLE_BIN_DIR 环境变量:"
    echo "  curl -L -o /tmp/sparkle-tools.zip https://github.com/sparkle-project/Sparkle/releases/latest/download/Sparkle-for-Swift-Package-Manager.zip"
    exit 1
fi

# ---------- 1. 更新版本号 ----------
OLD_MARKETING=$(grep -m1 'MARKETING_VERSION = ' "$PBXPROJ" | sed 's/.*MARKETING_VERSION = \(.*\);/\1/')
OLD_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION = ' "$PBXPROJ" | sed 's/.*CURRENT_PROJECT_VERSION = \(.*\);/\1/')
NEW_BUILD=$((OLD_BUILD + 1))

if [[ "$OLD_MARKETING" == "$VERSION" ]]; then
    echo "版本号已是 $VERSION，跳过 MARKETING_VERSION 更新"
else
    sed -i '' "s/MARKETING_VERSION = $OLD_MARKETING;/MARKETING_VERSION = $VERSION;/g" "$PBXPROJ"
fi
sed -i '' "s/CURRENT_PROJECT_VERSION = $OLD_BUILD;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PBXPROJ"
echo "版本: $VERSION (build $NEW_BUILD)"

# ---------- 2. 构建 Release ----------
echo "==> 构建 Release..."
mkdir -p "$BUILD_DIR"
xcodebuild -project "$ROOT/NotchMusic.xcodeproj" \
    -scheme NotchMusic \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -IDEPackageSupportDisableManifestSandbox=1 \
    OTHER_SWIFT_FLAGS="-disable-sandbox" \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    build >/dev/null

APP_PATH="$BUILD_DIR/NotchMusic.app"
[[ -d "$APP_PATH" ]] || { echo "错误: 构建产物不存在 $APP_PATH"; exit 1; }

# ---------- 3. 打包 DMG ----------
echo "==> 打包 DMG..."
mkdir -p "$DMG_DIR"
rm -f "$DMG_PATH"
hdiutil create -volname "NotchMusic $VERSION" \
    -srcfolder "$APP_PATH" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

# ---------- 4. Sparkle 签名 ----------
echo "==> 生成 EdDSA 签名..."
SIGN_OUTPUT=$("$SPARKLE_BIN_DIR/sign_update" "$DMG_PATH")
SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(stat -f%z "$DMG_PATH")
[[ -n "$SIGNATURE" ]] || { echo "错误: 签名失败: $SIGN_OUTPUT"; exit 1; }

# ---------- 5. 更新 appcast.xml ----------
echo "==> 更新 appcast.xml..."
python3 - "$APPCAST" "$VERSION" "$NEW_BUILD" "$TAG" "$DMG_NAME" "$SIGNATURE" "$LENGTH" "$NOTES" <<'PYEOF'
import sys, re
from datetime import datetime, timezone

path, version, build, tag, dmg, sig, length, notes = sys.argv[1:9]
pub_date = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S +0000')
url = f"https://github.com/Hoxxxxx/notch-music/releases/download/{tag}/{dmg}"
item = f'''        <item>
            <title>Version {version}</title>
            <description><![CDATA[{notes}]]></description>
            <pubDate>{pub_date}</pubDate>
            <enclosure
                url="{url}"
                sparkle:version="{build}"
                sparkle:shortVersionString="{version}"
                sparkle:edSignature="{sig}"
                length="{length}"
                type="application/octet-stream"
            />
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
        </item>
'''
s = open(path).read()
if f'sparkle:shortVersionString="{version}"' in s:
    s = re.sub(r'        <item>\n(.*?</item>\n)', item, s, count=1, flags=re.S)
else:
    s = s.replace('<items></items>', '<items>\n' + item + '        </items>')
open(path, 'w').write(s)
print("appcast.xml 已更新")
PYEOF

# ---------- 6. 提交并创建 Release ----------
echo "==> 提交版本变更..."
cd "$ROOT"
git add appcast.xml NotchMusic.xcodeproj/project.pbxproj
git commit -m "Release $VERSION (build $NEW_BUILD)" || true
git push origin main

echo "==> 创建 GitHub Release..."
if command -v gh >/dev/null; then
    gh release create "$TAG" "$DMG_PATH" \
        --repo "$REPO" \
        --title "$TAG" \
        --notes "$NOTES"
else
    echo "未安装 gh，请手动创建 Release 并上传 $DMG_PATH"
fi

echo ""
echo "✅ 发布完成: $TAG (build $NEW_BUILD)"
echo "   DMG: $DMG_PATH"
echo "   appcast: https://raw.githubusercontent.com/$REPO/main/appcast.xml"
