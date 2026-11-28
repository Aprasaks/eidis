"""JARVIS background wake listener — "Hey JARVIS" even when the app is closed.

- Runs as a LaunchAgent (dev.dechive.jarvis.wake). Listens to the default microphone locally;
  audio never leaves this Mac and is never written to disk.
- Model: openWakeWord "hey_jarvis_v0.1" (~/.jarvis-lab/wakeword/hey_jarvis_v0.1.onnx).
- On a hit it opens jarvis-mac://wake-dashboard. macOS launches JARVIS if it is not running,
  then JARVIS shows the core, says "Opening your dashboard, DECHIVE." and opens the dashboard.
- 10 s cooldown after a hit so one phrase triggers once.
- CPU saver: the model only runs while there is sound above the room's noise floor.
  The last 1.6 s of audio is kept so the start of "Hey" is not lost when the gate opens.
  After 2 s of quiet the gate closes and the model rests (idle CPU ~1% instead of ~10%).

- Crash guard: JARVIS sometimes crashes inside SwiftUI's own button handling (no app frames on
  the stack, see DiagnosticReports EidisMac-*.ips). Every 10 s this checks whether JARVIS vanished
  AND a fresh crash report appeared (waits up to 30 s for it); only then it relaunches JARVIS in the background.
  A normal quit (no crash report) is respected and JARVIS stays closed.

Run: ~/.jarvis-lab/speaker/venv/bin/python -I jarvis_wake_daemon.py
"""
import pathlib
import subprocess
import sys
import time
from collections import deque

import numpy as np
import sounddevice as sd
from openwakeword.model import Model

MODEL = pathlib.Path.home() / ".jarvis-lab/wakeword/hey_jarvis_v0.1.onnx"
# "이디스" 호출어 (tools/wakeword/train_eidis.py · P8 E3). 있으면 같이 듣는다.
EIDIS_MODEL = pathlib.Path.home() / ".jarvis-lab/wakeword/eidis_wake.onnx"
EIDIS_THRESHOLD = 0.8
RATE, CHUNK = 16000, 1280          # 80 ms frames (openWakeWord standard)
THRESHOLD = 0.6
COOLDOWN = 10.0
PREROLL = 20                       # frames kept before the gate opens (1.6 s)
HANGOVER = 25                      # frames the gate stays open after the last loud frame (2 s)
MIN_LEVEL = 180.0                  # never open below this RMS (int16), even in a silent room


def log(*parts):
    print(time.strftime("%H:%M:%S"), *parts, flush=True)


CRASH_DIR = pathlib.Path.home() / "Library/Logs/DiagnosticReports"


def jarvis_running():
    return subprocess.run(["/usr/bin/pgrep", "-x", "EidisMac"], capture_output=True).returncode == 0


def latest_crash():
    reports = list(CRASH_DIR.glob("EidisMac-*.ips"))
    return max((r.stat().st_mtime for r in reports), default=0.0)


class CrashGuard:
    """Relaunch JARVIS only when it vanished AND a new crash report shows up (within 30 s)."""
    def __init__(self):
        self.was_running = jarvis_running()
        self.seen_crash = latest_crash()
        self.vanished_at = None
        self.relaunches = []

    def check(self):
        running = jarvis_running()
        if self.was_running and not running:
            self.vanished_at = time.time()          # decide on the next ticks (report is written late)
        if self.vanished_at is not None:
            crash = latest_crash()
            if running:
                self.vanished_at = None             # someone already reopened it
                self.seen_crash = max(self.seen_crash, crash)
            elif crash > self.seen_crash:
                self.seen_crash, self.vanished_at = crash, None
                self.relaunches = [t for t in self.relaunches if time.time() - t < 600]
                if len(self.relaunches) < 3:        # at most 3 relaunches per 10 min
                    self.relaunches.append(time.time())
                    log("JARVIS crashed · relaunching in background")
                    subprocess.run(["/usr/bin/open", "-g", "-b", "dev.dechive.eidis"], check=False)
                    running = True
                else:
                    log("JARVIS crashed 3 times in 10 min · not relaunching")
            elif time.time() - self.vanished_at > 30:
                self.vanished_at = None
                log("JARVIS closed normally · leaving it closed")
        self.was_running = running

    def interval(self):
        return 2 if self.vanished_at is not None else 10


def main():
    models = [str(MODEL)] + ([str(EIDIS_MODEL)] if EIDIS_MODEL.exists() else [])
    model = Model(wakeword_models=models, inference_framework="onnx")
    last_hit = 0.0
    guard = CrashGuard()
    guard_tick = time.time()
    log("listening for 'Hey JARVIS'" + (" and 'EIDIS'" if len(models) > 1 else ""))
    with sd.InputStream(samplerate=RATE, channels=1, dtype="int16", blocksize=CHUNK) as stream:
        heard = 0.0
        last_minute = 0
        noise = 200.0                  # running estimate of the room's quiet level (RMS)
        preroll = deque(maxlen=PREROLL)
        open_frames = 0                # >0 while the gate is open
        while True:
            frames, _ = stream.read(CHUNK)
            pcm = frames[:, 0].copy()
            heard = max(heard, float(np.abs(pcm).max()))
            rms = float(np.sqrt(np.mean(pcm.astype(np.float32) ** 2)))
            loud = rms > max(MIN_LEVEL, noise * 2.5)
            if not loud and open_frames == 0:
                noise = noise * 0.98 + rms * 0.02      # learn the quiet level only while quiet
                preroll.append(pcm)
            else:
                if open_frames == 0:                   # gate opens: catch up on the buffered start
                    for old in preroll:
                        model.predict(old)
                    preroll.clear()
                open_frames = HANGOVER if loud else open_frames - 1
                scores = model.predict(pcm)
                jarvis = float(scores.get(MODEL.stem, 0.0))
                eidis = float(scores.get(EIDIS_MODEL.stem, 0.0))
                now = time.time()
                if jarvis >= THRESHOLD and now - last_hit > COOLDOWN:
                    # "Hey JARVIS" → 흰빛→금빛 코어 · Welcome home · 대시보드
                    last_hit = now
                    log(f"wake {jarvis:.2f}")
                    subprocess.run(["/usr/bin/open", "jarvis-mac://wake-dashboard"], check=False)
                    model.reset()
                elif eidis >= EIDIS_THRESHOLD and now - last_hit > COOLDOWN:
                    # "이디스" → "What can I help you with?" 후 바로 듣기
                    last_hit = now
                    log(f"eidis {eidis:.2f}")
                    subprocess.run(["/usr/bin/open", "jarvis-mac://wake-eidis"], check=False)
                    model.reset()
                if open_frames == 0:
                    model.reset()                      # gate closes: rest the model
            now = time.time()
            if now - guard_tick >= guard.interval():
                guard_tick = now
                guard.check()
            # once a minute: show the mic is actually delivering sound (0 = no mic permission)
            minute = int(now // 60)
            if minute != last_minute:
                if last_minute:
                    log(f"alive · peak level {int(heard)} · noise {int(noise)}")
                last_minute, heard = minute, 0.0

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
