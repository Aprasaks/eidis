"""Offline word-template experiment with openWakeWord mel frontend.
No microphone, no user samples, no app activation.
"""
import json, pathlib, tempfile, time
import numpy as np
from openwakeword.utils import AudioFeatures
from train_ko_prototype import synth

ROOT=pathlib.Path.home()/".jarvis-lab/wakeword"
TRAIN=["Yuna","Eddy (한국어(한국))","Flo (한국어(한국))","Reed (한국어(한국))"]
TEST=["Sandy (한국어(한국))","Shelley (한국어(한국))"]
POS=["자비스","자비스?"]
NEG=["서비스","자비","자비심","자바스크립트","오늘 날씨 알려줘","안녕하세요","지금 몇 시야","다시 시작해"]

def signature(front, pcm):
    # Keep a single foreground utterance. Trim low-energy boundary frames,
    # normalize level; reject silence, very short or too-long utterances.
    x=np.asarray(pcm,dtype=np.float64).reshape(-1)
    if len(x)<3200:raise ValueError("short")
    x=x-np.median(x)
    n=len(x)//320
    rms=np.sqrt(np.mean(x[:n*320].reshape(n,320)**2,axis=1))
    peak=float(np.max(rms))
    active=np.flatnonzero(rms>max(80,peak*.08))
    if peak<100 or len(active)<5:raise ValueError("no foreground voice")
    a=max(0,int(active[0])*320-320);b=min(len(x),(int(active[-1])+1)*320+320)
    x=x[a:b]
    if not 3200<=len(x)<=36000:raise ValueError("phrase duration")
    # Level normalization to reduce speaker volume and mic-distance variation.
    x=np.clip(x*6500/max(1,float(np.sqrt(np.mean(x*x)))),-32768,32767).astype(np.int16)
    padded=np.pad(x,(320,320))
    mel=front._get_melspectrogram(padded)
    # per-frequency cepstral shape retained; subtract frame broadband component
    mel=mel-mel.mean(axis=1,keepdims=True)
    mel=mel[::2]
    delta=np.gradient(mel,axis=0)
    feat=np.concatenate([mel,delta*.65],axis=1)
    feat=feat/np.maximum(1e-6,np.linalg.norm(feat,axis=1,keepdims=True))
    return feat.astype(np.float32)

def distance(a,b):
    # Whole-utterance constrained DTW with a path-length normalization.
    n,m=len(a),len(b)
    if max(n,m)/min(n,m)>2.4:return 2.
    c=np.clip(1-a@b.T,0,2)
    d=np.full((n+1,m+1),np.inf);d[0,0]=0
    for i in range(1,n+1):
        lo=max(1,int(i*m/n-m*.28));hi=min(m,int(i*m/n+m*.28)+1)
        for j in range(lo,hi+1):
            d[i,j]=c[i-1,j-1]+min(d[i-1,j-1],d[i-1,j]+.035,d[i,j-1]+.035)
    return float(d[n,m]/max(n,m))

def metrics(s, pos, neg):
    pd=min(distance(s,x) for x in pos)
    nd=min(distance(s,x) for x in neg)
    return pd,nd-pd

def decide(p,margin,max_distance,min_margin):
    return bool(np.isfinite(p) and np.isfinite(margin) and p<=max_distance and margin>=min_margin)

def calibrate(training):
    # All choices based on training voices only; held-out voices not consulted.
    rows=[]
    for voice,s,label in training:
        pos=[x for v,x,l in training if v!=voice and l]
        neg=[x for v,x,l in training if v!=voice and not l]
        rows.append((*metrics(s,pos,neg),label))
    # Select a criterion with no training cross-voice false alarms first.
    candidates=[]
    for p in sorted(set([r[0] for r in rows]+[.4])):
        for margin in sorted(set([r[1] for r in rows]+[.02,.05])):
            tp=sum(decide(a,b,p,margin) and l for a,b,l in rows)
            fp=sum(decide(a,b,p,margin) and not l for a,b,l in rows)
            candidates.append((fp,-tp, p,-margin))
    fp,ntp,p,nmargin=min(candidates)
    return p,-nmargin, -ntp,fp

def main():
    start=time.monotonic()
    front=AudioFeatures(inference_framework="onnx")
    training=[];test=[]
    with tempfile.TemporaryDirectory(prefix="jarvis-template-") as td:
        base=pathlib.Path(td)/"sample"
        for voice in TRAIN+TEST:
            for phrase in POS+NEG:
                # Held-out speakers and speech rates.
                for rate in ([180] if voice in TRAIN else [155,205]):
                    try:
                        sig=signature(front,synth(voice,phrase,rate,base))
                    except ValueError as e:
                        print("REJECTED",voice,phrase,str(e),flush=True);continue
                    if voice in TRAIN:training.append((voice,sig,phrase in POS))
                    else:test.append((voice,sig,phrase,rate,phrase in POS))
            print("PREPARED",voice,flush=True)
        d,m,tp,fp=calibrate(training)
        print("CALIBRATION",d,m,tp,fp,flush=True)
        pos=[s for _,s,l in training if l];neg=[s for _,s,l in training if not l]
        rows=[]
        for voice,s,phrase,rate,label in test:
            p,margin=metrics(s,pos,neg)
            detected=decide(p,margin,d,m)
            row=dict(voice=voice,phrase=phrase,rate=rate,positive=label,distance=p,margin=margin,detected=detected)
            rows.append(row);print(json.dumps(row,ensure_ascii=False),flush=True)
        report=dict(scope="synthetic holdout only",train=len(training),positive_detected=sum(r["detected"] and r["positive"] for r in rows),positive_total=sum(r["positive"] for r in rows),negative_detected=sum(r["detected"] and not r["positive"] for r in rows),negative_total=sum(not r["positive"] for r in rows),max_distance=d,min_margin=m,elapsed=round(time.monotonic()-start,2),rows=rows)
        (ROOT/"template_experiment_report.json").write_text(json.dumps(report,ensure_ascii=False,indent=2))
        print("REPORT",json.dumps({k:v for k,v in report.items() if k!="rows"},ensure_ascii=False),flush=True)
if __name__=="__main__":main()
