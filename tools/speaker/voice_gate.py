"""Local experimental speaker filter, not a security authorization boundary."""
import sys
sys.dont_write_bytecode = True
from pathlib import Path
# App invokes an isolated interpreter; import only the signed companion file.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
from voice_id import VoiceID, load_profile, similarity, SR
from collections import deque

WAKE_THRESHOLD = .25
COMMAND_THRESHOLD = .52
CHUNK = 2560
WAKE_MODEL = Path.home()/".jarvis-lab/wakeword/deka_ko_experimental.onnx"

def assess(model, owner, raw, threshold, min_seconds):
    try:
        score = similarity(owner, model.embed(np.frombuffer(raw,dtype="<i2"),min_seconds=min_seconds))
        return np.isfinite(score) and score >= threshold, score
    except ValueError:
        return False, None

def wake(model,owner):
    from openwakeword.model import Model
    detector=Model(wakeword_models=[str(WAKE_MODEL)],inference_framework="onnx")
    ring=deque(maxlen=20) # most recent 1.6s only
    pending=0
    peak=0.0
    cooldown=0
    print("READY",flush=True)
    while True:
        raw=sys.stdin.buffer.read(CHUNK)
        if len(raw)!=CHUNK:return
        ring.append(raw)
        score=float(max(detector.predict(np.frombuffer(raw,dtype="<i2")).values()))
        if not np.isfinite(score):raise ValueError("wake score")
        if cooldown:
            cooldown-=1
            continue
        if pending:
            peak=max(peak,score)
            pending-=1
            if pending:continue
            accepted,voice_score=assess(model,owner,b"".join(ring),WAKE_THRESHOLD,.25)
            ring.clear()
            if accepted:
                print(f"HIT {peak:.6f}",flush=True)
                while sys.stdin.buffer.read(CHUNK):pass
                return
            print("REJECT",flush=True)
            detector.reset()
            cooldown=10
            peak=0.0
        elif score>=.5:
            peak=score
            pending=2 # 160 ms to retain the ending phoneme

def command(model,owner):
    # Bound memory to the existing max command duration, reject excess input.
    data=sys.stdin.buffer.read(SR*2*120+2)
    if not data or len(data)>SR*2*120 or len(data)%2:
        print("REJECT",flush=True);return
    accepted,_=assess(model,owner,data,COMMAND_THRESHOLD,.25)
    print("ACCEPT" if accepted else "REJECT",flush=True)

def main():
    if len(sys.argv)!=2 or sys.argv[1] not in ("wake","command"):raise ValueError("mode")
    owner=load_profile()
    model=VoiceID()
    if sys.argv[1]=="wake":wake(model,owner)
    else:command(model,owner)
if __name__=="__main__":
    try:main()
    except Exception:
        print("ERROR",flush=True)
        sys.exit(1)
