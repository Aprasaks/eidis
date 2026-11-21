#!/bin/bash
set -e
cd "$(dirname "$0")"
exec "$HOME/.jarvis-lab/wakeword/venv/bin/python" -u tools/wakeword/deka_test.py
