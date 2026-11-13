#!/usr/bin/env bash
# 用主检出的虚拟环境跑测试，工作树共享同一套依赖。
set -euo pipefail
root=$(git rev-parse --path-format=absolute --git-common-dir)
main=$(cd "$(dirname "$root")" && pwd)
cd "$(git rev-parse --show-toplevel)"
exec "$main/.venv/bin/python" -m pytest -q "$@"
