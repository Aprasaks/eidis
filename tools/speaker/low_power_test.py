"""Offline comparison: synthetic fixtures, no mic and no personal profile."""
import time,tempfile,pathlib
import numpy as np
from voice_gate import QuietWake,WAKE_MODEL
from openwakeword.model import Model
from benchmark import synth
def run(blocks,low):
    np.random.seed(42)
    gate=QuietWake(Model(wakeword_models=[str(WAKE_MODEL)],inference_framework="onnx",ncpu=1),low)
    started=time.process_time()
    scores=[gate.push(p) for p in blocks]
    return max(scores,default=0.),gate.calls,gate.skipped,time.process_time()-started
def main():
    quiet=np.zeros((750,1280),dtype=np.int16)
    before=run(quiet,False);after=run(quiet,True)
    print("60 seconds synthetic silence: baseline",before,"gated",after,flush=True)
    assert after[1]==0 and after[0]==0
    rng=np.random.default_rng(24)
    results=[]
    with tempfile.TemporaryDirectory() as d:
        for voice in ["Yuna","Eddy (한국어(한국))","Sandy (한국어(한국))"]:
            pcm=synth(voice,"데카",155,pathlib.Path(d)/"sample.aiff")
            for amplitude,noise in [(1,0),(.1,4),(.03,8)]:
                data=np.pad(pcm.astype(float)*amplitude,(32000,32000))
                data=np.clip(data+rng.normal(0,noise,len(data)),-32768,32767).astype(np.int16)
                data=np.pad(data,(0,(-len(data))%1280)).reshape(-1,1280)
                base=run(data,False);new=run(data,True)
                results.append((base[0]>=.5,new[0]>=.5))
                print(voice,amplitude,noise,round(base[0],3),round(new[0],3),flush=True)
    print("baseline detected",sum(a for a,b in results),"gated detected",sum(b for a,b in results),"regressions",sum(a and not b for a,b in results),flush=True)
    assert not any(a and not b for a,b in results)
if __name__=="__main__":main()
