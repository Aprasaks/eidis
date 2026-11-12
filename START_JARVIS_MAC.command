#!/bin/bash
# Run the localhost server and a real JARVIS.app with privacy usage descriptions.
set -euo pipefail
cd "$(dirname "$0")" || exit 1

for tool in python3 swift plutil; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "필요한 도구를 찾지 못했습니다: $tool"
    echo "Xcode Command Line Tools는 xcode-select --install로 설치할 수 있습니다."
    read -r -p "Enter를 눌러 종료하세요."
    exit 1
  fi
done

export JARVIS_NO_BROWSER=1
python3 app.py &
server_pid=$!
cleanup() {
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT

sleep 1
if ! kill -0 "$server_pid" 2>/dev/null; then
  echo "로컬 서버 실행 실패. 이미 8765 포트를 사용하는 프로세스가 있는지 확인해 주세요."
  read -r -p "Enter를 눌러 종료하세요."
  exit 1
fi

echo "권한 설명을 포함한 JARVIS.app을 빌드합니다."
bash macos/scripts/package-app.sh
echo "앱 종료 시 로컬 서버도 종료됩니다."
open -W "dist/JARVIS.app"
