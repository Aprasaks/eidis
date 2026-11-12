#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")" || exit 1

if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3가 필요합니다."
  read -r -p "Enter를 눌러 종료하세요."
  exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
  echo "Xcode Command Line Tools (Swift)가 필요합니다. 먼저 xcode-select --install을 진행하세요."
  read -r -p "Enter를 눌러 종료하세요."
  exit 1
fi

export JARVIS_NO_BROWSER=1
python3 app.py &
server_pid=$!
cleanup() { kill "$server_pid" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

sleep 1
if ! kill -0 "$server_pid" 2>/dev/null; then
  echo "로컬 서버가 시작되지 않았습니다. 기존 8765 포트 사용 여부를 확인하세요."
  read -r -p "Enter를 눌러 종료하세요."
  exit 1
fi

echo "JARVIS macOS 셸을 시작합니다. 첫 실행은 Swift 컴파일 때문에 시간이 걸릴 수 있습니다."
swift run --package-path macos
