"""Local experimental speaker filter, not a security authorization boundary."""
import sys
sys.dont_write_bytecode = True
from pathlib import Path
# App invokes an isolated interpreter; import only the signed companion file.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import numpy as np
from voice_id import VoiceID, load_profile, similarity, SR
from collections import deque
import json,os,time

WAKE_THRESHOLD = .25
# English-only wake detection. The official openWakeWord "Hey Jarvis"
# model alone misses some voices speaking just "Jarvis", so supplement it
# with a locally trained English single-word model. Results are synthetic,
# not a real-owner microphone accuracy guarantee. Keep speaker verification.
WAKEWORD_THRESHOLD = .80
ENGLISH_SOLO_THRESHOLD = .75
COMMAND_THRESHOLD = .52
CHUNK = 2560
WAKE_MODELS = [
    Path.home()/".jarvis-lab/wakeword/hey_jarvis_v0.1.onnx",
    Path.home()/".jarvis-lab/wakeword/jarvis_en_wake.onnx",
]

def assess(model, owner, raw, threshold, min_seconds):
    try:
        score = similarity(owner, model.embed(np.frombuffer(raw,dtype="<i2"),min_seconds=min_seconds))
        return np.isfinite(score) and score >= threshold, score
    except ValueError:
        return False, None

# A deliberately conservative energy gate, not a speech classifier.
# Quiet input bypasses neural inference; retain pre-roll and a long tail
# so quiet initial/final consonants and model context are not discarded.
class QuietWake:
    def __init__(self, detector, low_power=True):
        self.detector=detector
        self.low_power=low_power
        self.history=deque(maxlen=20)
        self.tail=0
        self.calls=0
        self.skipped=0

    def push(self, pcm):
        self.history.append(pcm.copy())
        audible=float(np.sqrt(np.mean(pcm.astype(np.float32)**2))) >= 30.0
        if not self.low_power:
            return self.predict(pcm)
        if audible:
            if self.tail == 0:
                self.detector.reset()
                # Replay precisely the recent frames, including the onset.
                frames=[np.zeros(1280,dtype=np.int16)]*(20-len(self.history))+list(self.history)
                score=0.
                for frame in frames:
                    score=self.predict(frame)
                self.tail=25
                return score
            self.tail=25
        elif self.tail == 0:
            self.skipped+=1
            return 0.
        else:
            self.tail-=1
        return self.predict(pcm)

    def predict(self,pcm):
        self.calls+=1
        probabilities=self.detector.predict(pcm)
        official=float(probabilities.get("hey_jarvis_v0.1",0.))
        solo=float(probabilities.get("jarvis_en_wake",0.))
        if not (np.isfinite(official) and np.isfinite(solo)):
            raise ValueError("wake score")
        # Each detector has its own validated synthetic threshold. Map the
        # solo trigger onto the common 0.80..1.00 activation scale.
        solo_normalized=(WAKEWORD_THRESHOLD + (solo-ENGLISH_SOLO_THRESHOLD)*
                         ((1-WAKEWORD_THRESHOLD)/(1-ENGLISH_SOLO_THRESHOLD))
                         if solo>=ENGLISH_SOLO_THRESHOLD else 0.)
        return min(1., max(official,solo_normalized))

class WakeDiagnostics:
    """Last rolling numerical summary only; never PCM, transcript or embedding."""
    def __init__(self):
        self.path=Path.home()/".jarvis-lab/speaker/wake-diagnostics.json"
        self.started=time.monotonic()
        self.last=self.started
        self.frames=0
        self.max_rms=0.
        self.max_wake=0.
        self.candidates=0
        self.rejected=0
        self.last_candidate=None
        self.publish()
    def publish(self):
        value=dict(pid=os.getpid(),updated=time.time(),frames=self.frames,
                   peak_rms=round(self.max_rms,2),peak_wake=round(self.max_wake,4),
                   candidates=self.candidates,rejected=self.rejected,
                   last_candidate=self.last_candidate)
        tmp=self.path.with_suffix(".tmp")
        try:
            fd=os.open(tmp,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
            with os.fdopen(fd,"w") as f:json.dump(value,f)
            os.replace(tmp,self.path)
        except OSError:pass
    def frame(self,pcm,score):
        if time.monotonic()-self.started>300:return
        self.frames+=1
        self.max_rms=max(self.max_rms,float(np.sqrt(np.mean(pcm.astype(np.float32)**2))))
        self.max_wake=max(self.max_wake,score)
        if time.monotonic()-self.last>=3:
            self.publish()
            self.last=time.monotonic()
    def candidate(self,score,voice,accepted):
        if time.monotonic()-self.started>300:return
        self.candidates+=1
        self.rejected+=int(not accepted)
        self.last_candidate=dict(wake=round(score,4),voice=None if voice is None else round(voice,4),accepted=bool(accepted))
        self.publish()

def wake(model,owner,diagnostics=None):
    from openwakeword.model import Model
    detector=Model(wakeword_models=[str(path) for path in WAKE_MODELS],
                   inference_framework="onnx",ncpu=1)
    gate=QuietWake(detector)
    ring=deque(maxlen=20) # most recent 1.6s only
    pending=0
    peak=0.0
    cooldown=0
    print("READY",flush=True)
    while True:
        raw=sys.stdin.buffer.read(CHUNK)
        if len(raw)!=CHUNK:return
        ring.append(raw)
        pcm=np.frombuffer(raw,dtype="<i2")
        score=gate.push(pcm)
        if diagnostics:diagnostics.frame(pcm,score)
        if cooldown:
            cooldown-=1
            continue
        if pending:
            peak=max(peak,score)
            pending-=1
            if pending:continue
            accepted,voice_score=assess(model,owner,b"".join(ring),WAKE_THRESHOLD,.25)
            ring.clear()
            if diagnostics:diagnostics.candidate(peak,voice_score,accepted)
            if accepted:
                print(f"HIT {peak:.6f}",flush=True)
                while sys.stdin.buffer.read(CHUNK):pass
                return
            print("REJECT",flush=True)
            detector.reset()
            cooldown=10
            peak=0.0
        elif score>=WAKEWORD_THRESHOLD:
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
    if sys.argv[1]=="wake":wake(model,owner,WakeDiagnostics())
    else:command(model,owner)
if __name__=="__main__":
    try:main()
    except Exception:
        print("ERROR",flush=True)
        sys.exit(1)
