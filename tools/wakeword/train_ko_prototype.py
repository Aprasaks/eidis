"""Experimental local Korean classifier using openWakeWord streaming features.
Synthetic voice-disjoint holdout only. No real microphone/no deployment.
"""
import json, pathlib, subprocess, tempfile, time
import numpy as np
import onnx
from onnx import helper, TensorProto, numpy_helper
from sklearn.linear_model import LogisticRegression
from openwakeword.utils import AudioFeatures
from openwakeword.model import Model
from benchmark import audio, score

ROOT=pathlib.Path.home()/".jarvis-lab/wakeword"
DEST=ROOT/"jarvis_ko_experimental.onnx"
CHUNK=1280
N=16
TRAIN=["Yuna","Eddy (한국어(한국))","Flo (한국어(한국))","Reed (한국어(한국))"]
HOLDOUT=["Sandy (한국어(한국))","Shelley (한국어(한국))"]
POS=["자비스","자비스?"]
NEG=["서비스","자비","자비심", "잡지","비스킷","자전거","오늘 날씨 알려줘","안녕하세요","잠깐만","자동차","지금 몇 시야"]
rng=np.random.default_rng(21)
np.random.seed(21)

def synth(voice,phrase,rate,base):
    aiff=base.with_suffix(".aiff"); wav=base.with_suffix(".wav")
    subprocess.run(["/usr/bin/say","-v",voice,"-r",str(rate),"-o",str(aiff),phrase],check=True,capture_output=True,timeout=15)
    subprocess.run(["/opt/homebrew/bin/ffmpeg","-v","error","-y","-i",str(aiff),"-ac","1","-ar","16000","-c:a","pcm_s16le",str(wav)],check=True,capture_output=True,timeout=10)
    pcm=audio(wav).copy()
    if len(pcm)<1600 or not np.any(pcm):raise ValueError("bad audio")
    return pcm

def trim(pcm):
    # 20ms frame RMS, retain quiet phoneme margins
    frames=[np.sqrt(np.mean(np.square(x.astype(float)))) for x in np.array_split(pcm,max(1,len(pcm)//320))]
    peak=max(frames)
    active=np.flatnonzero(np.asarray(frames)>max(35,peak*.025))
    if not len(active):return pcm
    hop=len(pcm)/len(frames)
    a=max(0,int(active[0]*hop)-640); b=min(len(pcm),int((active[-1]+1)*hop)+640)
    return pcm[a:b]

def inputs(features,pcm,label,augment):
    pcm=trim(pcm)
    pre=int(rng.integers(24000,32000)); post=16000
    if augment:
        pcm=np.clip(pcm.astype(float)*rng.uniform(.5,1.15)+rng.normal(0,30,len(pcm)),-32768,32767).astype(np.int16)
    data=np.pad(pcm,(pre,post))
    if augment:data=np.clip(data.astype(float)+rng.normal(0,25,len(data)),-32768,32767).astype(np.int16)
    data=np.pad(data,(0,(-len(data))%CHUNK)).astype(np.int16)
    features.reset()
    x=[]; y=[]
    for i in range(0,len(data),CHUNK):
        features(data[i:i+CHUNK])
        end=i+CHUNK
        if end<16000:continue
        f=features.get_features(N).reshape(-1)
        delta=end-(pre+len(pcm))
        if label and -640<=delta<=6400:
            x.append(f); y.append(1)
        elif not label or end<pre-800 or delta>12000:
            # use sparse negatives, including nearby confusable syllables
            if i//CHUNK%2==0:x.append(f);y.append(0)
    return x,y

def export(clf,dim):
    w=clf.coef_.astype(np.float32).T; b=clf.intercept_.astype(np.float32)
    graph=helper.make_graph([
        helper.make_node("Flatten",["audio_features"],["flat"],axis=1),
        helper.make_node("MatMul",["flat","weights"],["z"]),
        helper.make_node("Add",["z","bias"],["logit"]),
        helper.make_node("Sigmoid",["logit"],["score"])
    ],"jarvis_ko_synthetic_prototype",[helper.make_tensor_value_info("audio_features",TensorProto.FLOAT,[1,N,dim//N])],[helper.make_tensor_value_info("score",TensorProto.FLOAT,[1,1])],[numpy_helper.from_array(w,"weights"),numpy_helper.from_array(b,"bias")])
    if not np.all(np.isfinite(w)) or not np.all(np.isfinite(b)):
        raise ValueError("non-finite model weights")
    model=helper.make_model(graph,opset_imports=[helper.make_opsetid("",13)],ir_version=8)
    onnx.checker.check_model(model)
    tmp=DEST.with_suffix(".tmp.onnx");onnx.save(model,str(tmp));tmp.replace(DEST)

def main():
    start=time.monotonic()
    features=AudioFeatures(inference_framework="onnx")
    x=[]; y=[]; valid=0
    with tempfile.TemporaryDirectory(prefix="jarvis-ko-synthetic-") as td:
        base=pathlib.Path(td)
        for voice in TRAIN:
            for j,phrase in enumerate(POS+NEG):
                pcm=synth(voice,phrase,180,base/"sample")
                for augment in [False,True]:
                    a,b=inputs(features,pcm,phrase in POS,augment)
                    x.extend(a);y.extend(b)
                valid+=1
            print("TRAIN_VOICE",voice,"clips",valid,flush=True)
        clf=LogisticRegression(C=.1,class_weight="balanced",max_iter=1000,random_state=21)
        clf.fit(np.asarray(x),np.asarray(y));export(clf,len(x[0]))
        print("EXPORTED",DEST,"rows",len(y),"positives",sum(y),flush=True)
        m=Model(wakeword_models=[str(DEST)],inference_framework="onnx")
        rows=[]
        # Entire held-out voices, new rates, and new negative phrases.
        for voice in HOLDOUT:
            for phrase in POS+NEG+["자바스크립트","다시 시작해","지금부터 시작합니다"]:
                for rate in (155,205):
                    pcm=synth(voice,phrase,rate,base/"sample")
                    peak,elapsed,duration=score(m,trim(pcm))
                    row=dict(voice=voice,phrase=phrase,rate=rate,positive=phrase in POS,score=round(peak,5),detected=peak>=.5)
                    rows.append(row);print(json.dumps(row,ensure_ascii=False),flush=True)
        positives=[r for r in rows if r["positive"]];negatives=[r for r in rows if not r["positive"]]
        report=dict(scope="synthetic voice-disjoint holdout only",threshold=.5,train_clips=valid,train_frames=len(y),positive_detected=sum(r["detected"] for r in positives),positive_total=len(positives),negative_detected=sum(r["detected"] for r in negatives),negative_total=len(negatives),elapsed=round(time.monotonic()-start,2),rows=rows)
        (ROOT/"jarvis_ko_experimental_report.json").write_text(json.dumps(report,ensure_ascii=False,indent=2))
        print("REPORT",json.dumps({k:v for k,v in report.items() if k!="rows"},ensure_ascii=False),flush=True)
        print("NOT APPROVED FOR LIVE OR ALWAYS-ON USE",flush=True)
if __name__=="__main__":main()
