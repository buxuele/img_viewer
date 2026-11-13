#!/usr/bin/env bash
# 编译并运行不依赖界面的逻辑测试。
set -euo pipefail
cd "$(dirname "$0")/.."

output=$(mktemp -d)/imgviewer_tests
swiftc -O \
  Sources/ImgViewer/ImageLibrary.swift \
  Sources/ImgViewer/SettingsStore.swift \
  Sources/ImgViewer/CanvasState.swift \
  tests/main.swift \
  -o "$output"
"$output"
