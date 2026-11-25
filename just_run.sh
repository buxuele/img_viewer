#!/usr/bin/env bash
# 构建并前台启动照片查看器，终端会一直占用到应用退出。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="照片查看器"
BUNDLE=".build/Build/Products/Release/ImgViewer.app"
BINARY="$BUNDLE/Contents/MacOS/ImgViewer"

printf '\033]0;%s\007' "$APP_NAME"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "缺少 xcodegen，请先安装：brew install xcodegen"
  exit 1
fi

if [ ! -d ImgViewer.xcodeproj ] || [ project.yml -nt ImgViewer.xcodeproj/project.pbxproj ]; then
  xcodegen generate
fi

needs_build=0
if [ ! -x "$BINARY" ]; then
  needs_build=1
elif find Sources project.yml -newer "$BINARY" -type f | grep -q .; then
  needs_build=1
fi

if [ "$needs_build" = 1 ]; then
  xcodebuild -project ImgViewer.xcodeproj -scheme ImgViewer -configuration Release -derivedDataPath .build build
fi

bash scripts/sign_app.sh

if pgrep -f "$BINARY" >/dev/null 2>&1; then
  echo "$APP_NAME 已经在运行"
  open "$BUNDLE"
  exit 0
fi

exec "$BINARY"
