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

# The server process merely existing is not proof that HTTP is serving.
# Verify this exact local JARVIS diagnostics endpoint before opening the app.
ready=0
for attempt in {1..30}; do
  if ! kill -0 "$server_pid" 2>/dev/null; then
    break
  fi
  if python3 -c '
import json
from urllib.request import urlopen
with urlopen("http://127.0.0.1:8765/api/diagnostics", timeout=1) as response:
    report = json.load(response)
assert report.get("scope") == "local_read_only"
assert report.get("server", {}).get("status") == "reachable"
' >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.25
done
if [ "$ready" -ne 1 ]; then
  echo "로컬 자비스 서버 준비 확인 실패."
  echo "8765 포트 중복, Python 오류 또는 저장소 최신 버전을 확인해 주세요."
  echo "진단이 실패해도 다른 프로세스나 포트를 강제로 종료하지 않습니다."
  read -r -p "Enter를 눌러 종료하세요."
  exit 1
fi
echo "로컬 자비스 서버 연결 확인 완료 (읽기 전용 진단 응답)."

echo "권한 설명을 포함한 JARVIS.app을 빌드합니다."
bash macos/scripts/package-app.sh
echo "앱 종료 시 로컬 서버도 종료됩니다."
open -W "dist/JARVIS.app"
