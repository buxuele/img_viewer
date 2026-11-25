#!/usr/bin/env bash
# 给应用加上沙盒授权并做临时签名，本地与打包共用。
set -euo pipefail
cd "$(dirname "$0")/.."

APP=${1:-.build/Build/Products/Release/ImgViewer.app}
ENTITLEMENTS="Sources/ImgViewer/ImgViewer.entitlements"

if [ ! -d "$APP" ]; then
  echo "应用不存在：$APP"
  exit 1
fi

codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP"
