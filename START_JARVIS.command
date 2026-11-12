#!/bin/bash
cd "$(dirname "$0")" || exit 1
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3가 필요합니다. python.org 또는 Homebrew를 통해 설치해 주세요."
  read -r -p "Enter를 눌러 닫으세요."
  exit 1
fi
python3 app.py
status=$?
echo "JARVIS 종료 (코드: $status)"
read -r -p "Enter를 눌러 닫으세요."
