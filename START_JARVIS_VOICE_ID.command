#!/bin/bash
set -e
cd "$(dirname "$0")"
exec "$HOME/.jarvis-lab/speaker/venv/bin/python" -u tools/speaker/enroll.py
