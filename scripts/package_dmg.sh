#!/usr/bin/env bash
# 把 Release 应用打成可分发的 dmg，本地与 CI 共用。
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE=".build/Build/Products/Release/ImgViewer.app"
if [ ! -d "$SOURCE" ]; then
  echo "先构建 Release 应用：.build/Build/Products/Release/ImgViewer.app 不存在"
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$SOURCE/Contents/Info.plist")
DIST="dist"
STAGE=$(mktemp -d)/dmg
mkdir -p "$DIST" "$STAGE"

cp -R "$SOURCE" "$STAGE/照片查看器.app"
ln -s /Applications "$STAGE/Applications"
codesign --force --deep --sign - "$STAGE/照片查看器.app"

rm -f "$DIST/ImgViewer-$VERSION.dmg"
hdiutil create \
  -volname "照片查看器" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DIST/ImgViewer-$VERSION.dmg" >/dev/null

rm -rf "$STAGE"
echo "已生成 $DIST/ImgViewer-$VERSION.dmg"
