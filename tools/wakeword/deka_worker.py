"""One-shot local DEKA detector. Receives only 16 kHz mono PCM from the Mac app."""
import pathlib
import sys
import numpy as np
from openwakeword.model import Model

MODEL = pathlib.Path.home() / ".jarvis-lab/wakeword/deka_ko_experimental.onnx"
CHUNK = 2560

def main():
    model = Model(wakeword_models=[str(MODEL)], inference_framework="onnx")
    print("READY", flush=True)
    while True:
        raw = sys.stdin.buffer.read(CHUNK)
        if len(raw) != CHUNK:
            return
        score = float(max(model.predict(np.frombuffer(raw, dtype="<i2")).values()))
        if not np.isfinite(score):
            raise ValueError("invalid score")
        if score >= .5:
            print(f"HIT {score:.6f}", flush=True)
            # Keep the pipe open until the app releases its capture.
            while sys.stdin.buffer.read(CHUNK):
                pass
            return

if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("ERROR", flush=True)
        sys.exit(1)
