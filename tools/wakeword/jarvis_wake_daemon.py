"""JARVIS background wake listener — "Hey JARVIS" even when the app is closed.

- Runs as a LaunchAgent (dev.dechive.jarvis.wake). Listens to the default microphone locally;
  audio never leaves this Mac and is never written to disk.
- Model: openWakeWord "hey_jarvis_v0.1" (~/.jarvis-lab/wakeword/hey_jarvis_v0.1.onnx).
- On a hit it opens jarvis-mac://wake-dashboard. macOS launches JARVIS if it is not running,
  then JARVIS shows the core, says "Opening your dashboard, DECHIVE." and opens the dashboard.
- 10 s cooldown after a hit so one phrase triggers once.

Run: ~/.jarvis-lab/speaker/venv/bin/python -I jarvis_wake_daemon.py
"""
import pathlib
import subprocess
import sys
import time

import numpy as np
import sounddevice as sd
from openwakeword.model import Model

MODEL = pathlib.Path.home() / ".jarvis-lab/wakeword/hey_jarvis_v0.1.onnx"
RATE, CHUNK = 16000, 1280          # 80 ms frames (openWakeWord standard)
THRESHOLD = 0.6
COOLDOWN = 10.0


def log(*parts):
    print(time.strftime("%H:%M:%S"), *parts, flush=True)


def main():
    model = Model(wakeword_models=[str(MODEL)], inference_framework="onnx")
    last_hit = 0.0
    log("listening for 'Hey JARVIS'")
    with sd.InputStream(samplerate=RATE, channels=1, dtype="int16", blocksize=CHUNK) as stream:
        heard = 0.0
        while True:
            frames, _ = stream.read(CHUNK)
            pcm = frames[:, 0]
            heard = max(heard, float(np.abs(pcm).max()))
            score = float(max(model.predict(pcm).values()))
            now = time.time()
            if score >= THRESHOLD and now - last_hit > COOLDOWN:
                last_hit = now
                log(f"wake {score:.2f}")
                subprocess.run(["/usr/bin/open", "jarvis-mac://wake-dashboard"], check=False)
                model.reset()
            # once a minute: show the mic is actually delivering sound (0 = no mic permission)
            if int(now) % 60 == 0 and heard >= 0:
                log(f"alive · peak level {int(heard)}")
                heard = -1.0
            elif int(now) % 60 == 1:
                heard = max(heard, 0.0)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
