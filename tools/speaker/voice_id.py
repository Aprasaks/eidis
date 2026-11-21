"""Offline DEKA speaker verification lab, not an authorization mechanism."""
import os
os.environ["HF_HUB_OFFLINE"]="1"
os.environ["HF_HUB_DISABLE_TELEMETRY"]="1"
import pathlib
import numpy as np
import torch
from speechbrain.inference.speaker import EncoderClassifier

ROOT=pathlib.Path.home()/".jarvis-lab/speaker"
MODEL=ROOT/"model"
PROFILE=ROOT/"owner-voice-v1.npz"
REVISION="a9f171aee6b706ea72b35dfe6d9dbd07947c2555"
SR=16000
class VoiceID:
    def __init__(self):
        torch.set_num_threads(2)
        self.model=EncoderClassifier.from_hparams(
            source=str(MODEL), savedir=str(ROOT/"runtime"),
            overrides={"pretrained_path":str(MODEL)},run_opts={"device":"cpu"})
    def embed(self,pcm,min_seconds=1.5):
        x=np.asarray(pcm,dtype=np.float32).reshape(-1)/32768.0
        if not np.isfinite(x).all() or len(x)<SR*min_seconds:raise ValueError("too short")
        frames=x[:len(x)//320*320].reshape(-1,320)
        rms=np.sqrt(np.mean(frames**2,axis=1))
        active=np.flatnonzero(rms>max(.0015,float(np.max(rms))*.04))
        if len(active)*.02<min_seconds:raise ValueError("not enough audible speech")
        x=x[max(0,active[0]*320-1600):min(len(x),(active[-1]+1)*320+1600)]
        if np.mean(np.abs(x)>=.999)>.01:raise ValueError("clipped")
        with torch.inference_mode():
            e=self.model.encode_batch(torch.from_numpy(x).unsqueeze(0)).cpu().numpy().reshape(-1)
        if e.shape!=(192,) or not np.isfinite(e).all() or np.linalg.norm(e)<1e-6:raise ValueError("bad embedding")
        return (e/np.linalg.norm(e)).astype(np.float32)

def centroid(embeddings):
    e=np.mean(np.asarray(embeddings),axis=0)
    if e.shape!=(192,) or not np.isfinite(e).all() or np.linalg.norm(e)<1e-6:raise ValueError("bad centroid")
    return e/np.linalg.norm(e)

def similarity(a,b):
    return float(np.clip(np.dot(a,b),-1,1))

def load_profile():
    # Never deserialize arbitrary objects or expose biometric coordinates.
    with np.load(PROFILE,allow_pickle=False) as saved:
        e=saved["embedding"]
        rev=str(saved["revision"].item())
    if rev!=REVISION or e.shape!=(192,) or not np.isfinite(e).all() or abs(float(np.linalg.norm(e))-1)>.01:
        raise ValueError("invalid voice profile")
    if PROFILE.stat().st_mode & 0o077:
        raise ValueError("voice profile permissions must be owner-only")
    return e.astype(np.float32)
