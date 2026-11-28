"""Offline synthetic "EIDIS" (이디스) wake word classifier on openWakeWord features (기획서 P8 E3).

- 학습 음성: 로컬 Kokoro(영어 목소리 여러 개, 127.0.0.1:8792) + macOS say (영어, 한국어 유나).
- 사용자 녹음은 쓰지 않는다. 검증은 학습에 쓰지 않은 목소리·속도·문장으로만 한다 (정확도 보장 아님).
- 결과: ~/.jarvis-lab/wakeword/eidis_wake.onnx + eidis_report.json
Run: ~/.jarvis-lab/wakeword/venv/bin/python -I tools/wakeword/train_eidis.py
"""
import json, pathlib, subprocess, sys, tempfile, time, urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import numpy as np
from sklearn.neural_network import MLPClassifier
import onnx
from onnx import helper, TensorProto, numpy_helper
from openwakeword.utils import AudioFeatures
from openwakeword.model import Model
import train_ko_prototype as trainer
from benchmark import audio, score

ROOT = pathlib.Path.home() / ".jarvis-lab/wakeword"
trainer.DEST = ROOT / "eidis_wake.onnx"

KOKORO_TRAIN = ["af_heart", "af_bella", "af_nicole", "af_sarah", "af_sky", "af_alloy", "af_aoede", "af_jessica",
                "af_kore", "af_river", "am_adam", "am_michael", "am_echo", "am_eric", "am_fenrir", "am_liam",
                "am_puck", "bf_emma", "bf_isabella", "bf_alice", "bm_george", "bm_lewis", "bm_daniel", "bm_fable"]
KOKORO_HOLDOUT = ["af_nova", "am_onyx", "bf_lily", "am_santa"]
SAY_TRAIN = ["Samantha", "Daniel", "Karen", "Rishi"]
SAY_HOLDOUT = ["Moira", "Shelley (영어(미국))"]
KO_TRAIN = ["Yuna"]
KO_HOLDOUT = ["Sandy (한국어(한국))"]

POS = ["Eedis.", "Eedis?", "Hey Eedis.", "Edis!", "Eadis."]
POS_KO = ["이디스", "이디스?", "이디스야"]
NEG = ["Edith.", "Edith?", "this", "is this it", "eat this", "easy", "Eddie", "Eddie's", "needs", "Idris", "Jarvis",
       "Hey Jarvis", "it is", "it is.", "the disk", "Ethan", "Eden", "editor", "these days", "geez", "radish", "Paris",
       "teeth", "what's the weather today", "open the dashboard", "I need this", "see this", "hey there",
       "Edison", "Indies", "EDS", "edits", "Eddy", "aid us", "feed this", "Idaho", "eighties", "deeds", "D C"]
NEG_KO = ["이거", "이따가", "디스", "있지", "이디야", "오늘 날씨 알려줘", "이제 그만", "디저트"]
HOLDOUT_NEG = ["meet us", "beat this", "Lydia", "read this", "please", "is it", "edible", "Didi", "lead this",
               "Eddie said", "edit this", "he did this"]


def export_mlp(clf, dim):
    w1, w2 = [w.astype(np.float32) for w in clf.coefs_]; b1, b2 = [b.astype(np.float32) for b in clf.intercepts_]
    graph = helper.make_graph([
        helper.make_node("Flatten", ["audio_features"], ["flat"], axis=1),
        helper.make_node("MatMul", ["flat", "w1"], ["h0"]), helper.make_node("Add", ["h0", "b1"], ["h1"]),
        helper.make_node("Relu", ["h1"], ["h"]),
        helper.make_node("MatMul", ["h", "w2"], ["z"]), helper.make_node("Add", ["z", "b2"], ["logit"]),
        helper.make_node("Sigmoid", ["logit"], ["score"])
    ], "eidis_wake_mlp",
        [helper.make_tensor_value_info("audio_features", TensorProto.FLOAT, [1, trainer.N, dim // trainer.N])],
        [helper.make_tensor_value_info("score", TensorProto.FLOAT, [1, 1])],
        [numpy_helper.from_array(w1, "w1"), numpy_helper.from_array(b1, "b1"),
         numpy_helper.from_array(w2, "w2"), numpy_helper.from_array(b2, "b2")])
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 13)], ir_version=8)
    onnx.checker.check_model(model)
    tmp = trainer.DEST.with_suffix(".tmp.onnx"); onnx.save(model, str(tmp)); tmp.replace(trainer.DEST)


def kokoro(voice, phrase, speed, base):
    wav24 = base.with_suffix(".k.wav"); wav = base.with_suffix(".wav")
    body = json.dumps({"text": phrase, "voice": voice, "speed": speed}).encode()
    req = urllib.request.Request("http://127.0.0.1:8792/tts", data=body, headers={"Content-Type": "application/json"})
    wav24.write_bytes(urllib.request.urlopen(req, timeout=60).read())
    subprocess.run(["/opt/homebrew/bin/ffmpeg", "-v", "error", "-y", "-i", str(wav24), "-ac", "1", "-ar", "16000",
                    "-c:a", "pcm_s16le", str(wav)], check=True, capture_output=True, timeout=10)
    pcm = audio(wav).copy()
    if len(pcm) < 1600 or not np.any(pcm): raise ValueError("bad audio")
    return pcm


def clips(holdout):
    """(source, voice, phrase, rate/speed, positive)"""
    k = KOKORO_HOLDOUT if holdout else KOKORO_TRAIN
    s = SAY_HOLDOUT if holdout else SAY_TRAIN
    ko = KO_HOLDOUT if holdout else KO_TRAIN
    neg = NEG + (HOLDOUT_NEG if holdout else [])
    speeds = (0.85, 1.1) if holdout else (1.0,)
    rates = (155, 210) if holdout else (180,)
    for v in k:
        for p in POS + neg:
            for sp in speeds: yield ("kokoro", v, p, sp, p in POS)
    for v in s:
        for p in POS + neg:
            for r in rates: yield ("say", v, p, r, p in POS)
    for v in ko:
        for p in POS_KO + NEG_KO:
            for r in rates: yield ("say", v, p, r, p in POS_KO)


def synth(src, voice, phrase, rate, base):
    return kokoro(voice, phrase, rate, base) if src == "kokoro" else trainer.synth(voice, phrase, rate, base)


def main():
    start = time.monotonic()
    features = AudioFeatures(inference_framework="onnx")
    x, y, n = [], [], 0
    with tempfile.TemporaryDirectory(prefix="eidis-wake-") as td:
        base = pathlib.Path(td) / "clip"
        for src, voice, phrase, rate, positive in clips(False):
            try:
                pcm = synth(src, voice, phrase, rate, base)
            except Exception as e:
                print("SKIP", src, voice, phrase, e, flush=True); continue
            for augment in (False, True, True) if positive else (False, True, True):
                a, b = trainer.inputs(features, pcm, positive, augment)
                x.extend(a); y.extend(b)
            n += 1
            if n % 50 == 0: print("clips", n, flush=True)
        X = np.asarray(x, dtype=np.float32); Y = np.asarray(y)
        # 균형: 양성 프레임을 반복해서 음성과 비슷한 수로 맞춘다 (MLP에는 class_weight가 없다)
        pos_idx = np.flatnonzero(Y == 1); neg_idx = np.flatnonzero(Y == 0)
        rep = np.random.default_rng(3).choice(pos_idx, size=max(0, len(neg_idx) // 2 - len(pos_idx)))
        idx = np.concatenate([neg_idx, pos_idx, rep])
        clf = MLPClassifier(hidden_layer_sizes=(64,), alpha=1e-3, max_iter=300, early_stopping=True, random_state=21)
        clf.fit(X[idx], Y[idx]); export_mlp(clf, X.shape[1])
        print("EXPORTED", trainer.DEST, "rows", len(y), "positives", sum(y), flush=True)

        m = Model(wakeword_models=[str(trainer.DEST)], inference_framework="onnx")
        rows = []
        for src, voice, phrase, rate, positive in clips(True):
            try:
                pcm = synth(src, voice, phrase, rate, base)
            except Exception:
                continue
            peak, _, _ = score(m, trainer.trim(pcm))
            rows.append(dict(src=src, voice=voice, phrase=phrase, rate=rate, positive=positive, score=round(float(peak), 4)))
        report = dict(scope="synthetic voice-disjoint holdout only", train_clips=n, train_frames=len(y),
                      elapsed=round(time.monotonic() - start, 1), rows=rows)
        for th in (0.5, 0.6, 0.7, 0.8, 0.9):
            pos = [r for r in rows if r["positive"]]; neg = [r for r in rows if not r["positive"]]
            report[f"th{th}"] = dict(detected=f'{sum(r["score"] >= th for r in pos)}/{len(pos)}',
                                     false=f'{sum(r["score"] >= th for r in neg)}/{len(neg)}',
                                     false_phrases=sorted({r["phrase"] for r in neg if r["score"] >= th}))
        (ROOT / "eidis_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
        print("REPORT", json.dumps({k: v for k, v in report.items() if k != "rows"}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
