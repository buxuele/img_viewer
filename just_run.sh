#!/usr/bin/env bash
# 一键启动照片查看器：准备虚拟环境、安装依赖、检查端口，就绪后打开浏览器。
set -euo pipefail
cd "$(dirname "$0")"

PORT=8770
APP_NAME="照片查看器"
VENV=.venv
PYTHON=${PYTHON:-python3.14}

printf '\033]0;%s:%s\007' "$APP_NAME" "$PORT"

if [ ! -x "$VENV/bin/python" ]; then
  echo "创建虚拟环境"
  "$PYTHON" -m venv "$VENV"
fi

if ! "$VENV/bin/python" -c "import fastapi, uvicorn" >/dev/null 2>&1; then
  echo "安装依赖"
  "$VENV/bin/python" -m pip install --disable-pip-version-check -q -r requirements.txt
fi

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  if curl -fsS "http://127.0.0.1:$PORT/api/health" 2>/dev/null | grep -q '"ok": *true'; then
    echo "$APP_NAME 已经在运行：http://127.0.0.1:$PORT"
    open "http://127.0.0.1:$PORT"
    exit 0
  fi
  echo "端口 $PORT 被其他程序占用"
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN
  exit 1
fi

(
  for _ in $(seq 1 120); do
    if curl -fsS "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
      open "http://127.0.0.1:$PORT"
      exit 0
    fi
    sleep 0.1
  done
) &

exec "$VENV/bin/python" -m uvicorn app.main:app --host 127.0.0.1 --port "$PORT"
