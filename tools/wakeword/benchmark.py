"""Offline smoke test: no microphone, no network, no personal recordings.
Synthetic examples are not a real-speaker accuracy or false-alarm benchmark.
"""
import json
import pathlib
import subprocess
import tempfile
import time
import wave

import numpy as np
import openwakeword
from openwakeword.model import Model

MODEL_ROOT = pathlib.Path(openwakeword.__file__).parent / "resources/models"
MODEL = MODEL_ROOT / "hey_jarvis_v0.1.onnx"
CHUNK = 1280
THRESHOLD = 0.5

def audio(path):
    with wave.open(str(path), "rb") as f:
        assert (f.getnchannels(), f.getsampwidth(), f.getframerate()) == (1, 2, 16000)
        return np.frombuffer(f.readframes(f.getnframes()), dtype="<i2")

def score(model, pcm):
    model.reset()
    padded = np.pad(pcm, (16000, 16000))
    padded = np.pad(padded, (0, (-len(padded)) % CHUNK))
    t = time.perf_counter()
    scores = [max(model.predict(padded[i:i+CHUNK]).values()) for i in range(0,len(padded),CHUNK)]
    elapsed = time.perf_counter() - t
    return float(max(scores)), elapsed, len(padded)/16000

def main():
    m = Model(wakeword_models=[str(MODEL)], inference_framework="onnx")
    tests = []
    for voice, phrases in [
        ("Yuna", ["자비스", "자비스?", "헤이 자비스", "서비스", "자비", "오늘 날씨 알려줘"]),
        ("Eddy (한국어(한국))", ["자비스", "자비스?", "헤이 자비스", "서비스", "자비", "오늘 날씨 알려줘"]),
        ("Samantha", ["Jarvis", "Hey Jarvis", "service", "today's weather"]),
        ("Daniel", ["Jarvis", "Hey Jarvis", "service", "today's weather"]),
    ]:
        for phrase in phrases:
            for rate in (160,210):
                tests.append((voice,phrase,rate))
    results=[]
    with tempfile.TemporaryDirectory(prefix="jarvis-wake-synthetic-") as td:
        dest=pathlib.Path(td)
        for i,(voice,phrase,rate) in enumerate(tests):
            aiff=dest/f"{i}.aiff"; wav=dest/f"{i}.wav"
            try:
                subprocess.run(["/usr/bin/say","-v",voice,"-r",str(rate),"-o",str(aiff),phrase],check=True,capture_output=True,timeout=15)
                subprocess.run(["/opt/homebrew/bin/ffmpeg","-v","error","-y","-i",str(aiff),"-ac","1","-ar","16000","-c:a","pcm_s16le",str(wav)],check=True,capture_output=True,timeout=10)
                pcm=audio(wav)
                if len(pcm)<1600 or not np.any(pcm):
                    raise ValueError("invalid synthetic audio")
                peak,elapsed,duration=score(m,pcm)
                row=dict(voice=voice,phrase=phrase,rate=rate,score=round(peak,5),detected=peak>=THRESHOLD,elapsed=round(elapsed,4),duration=round(duration,3))
            except (subprocess.SubprocessError,ValueError,AssertionError) as e:
                row=dict(voice=voice,phrase=phrase,rate=rate,error=type(e).__name__)
            results.append(row)
            print(json.dumps(row,ensure_ascii=False),flush=True)
    p,t,d=score(m,np.zeros(16000*5,dtype=np.int16))
    print(json.dumps(dict(silence_score=p,silence_elapsed=t,silence_duration=d)),flush=True)
    print("TOTAL",len(results),"valid",sum("score" in r for r in results),flush=True)
if __name__=="__main__":
    main()
