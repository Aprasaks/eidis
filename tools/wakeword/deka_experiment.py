"""DEKA offline comparison. No microphone or production integration."""
import json,pathlib,tempfile,time
import numpy as np
from openwakeword.utils import AudioFeatures
from openwakeword.model import Model
from sklearn.linear_model import LogisticRegression
from train_ko_prototype import synth,inputs
import train_ko_prototype as trainer
from template_experiment import signature,metrics,decide,calibrate
from benchmark import score
ROOT=pathlib.Path.home()/".jarvis-lab/wakeword"
POS=["데카","데카?"]
NEG=["내가","네가","대가","데이터","테카","데크","델타","대카","자비스","데카페인","오늘 날씨","안녕하세요"]
UNSEEN=["내가 할게","대가를 치르다","네가 해","테크","데칼","지금 몇 시야","카드","네"]
TRAIN=["Yuna","Eddy (한국어(한국))","Flo (한국어(한국))","Reed (한국어(한국))"]
TEST=["Sandy (한국어(한국))","Shelley (한국어(한국))"]
def main():
    start=time.monotonic()
    front=AudioFeatures(inference_framework="onnx")
    training=[];test=[];x=[];y=[]
    with tempfile.TemporaryDirectory(prefix="deka-synthetic-") as td:
        base=pathlib.Path(td)/"sample"
        for voice in TRAIN+TEST:
            is_train=voice in TRAIN
            for phrase in POS+NEG+([] if is_train else UNSEEN):
                for rate in ([175,205] if is_train and phrase in POS else [180] if is_train else [155,210]):
                    pcm=synth(voice,phrase,rate,base)
                    try: sig=signature(front,pcm)
                    except ValueError: sig=None
                    if is_train:
                        if sig is not None:training.append((voice,sig,phrase in POS))
                        for aug in [False,True]:
                            a,b=inputs(front,pcm,phrase in POS,aug);x.extend(a);y.extend(b)
                    else:test.append((voice,phrase,rate,pcm,sig,phrase in POS))
            print("PREPARED",voice,flush=True)
        arr=np.asarray(x,dtype=np.float64)
        if not np.isfinite(arr).all():raise ValueError("invalid embeddings")
        clf=LogisticRegression(C=.05,solver="liblinear",class_weight="balanced",max_iter=1000,random_state=21)
        clf.fit(arr,y)
        trainer.DEST=ROOT/"deka_ko_experimental.onnx"
        trainer.export(clf,arr.shape[1]);trainer.DEST.chmod(0o600)
        mdl=Model(wakeword_models=[str(trainer.DEST)],inference_framework="onnx")
        d,m,tp,fp=calibrate(training)
        print("TEMPLATE CALIBRATION",d,m,tp,fp,flush=True)
        pos=[s for _,s,l in training if l];neg=[s for _,s,l in training if not l]
        rows=[]
        for voice,phrase,rate,pcm,sig,label in test:
            peak,_,_=score(mdl,pcm)
            td,margin=metrics(sig,pos,neg) if sig is not None else (2.,-2.)
            row=dict(voice=voice,phrase=phrase,rate=rate,positive=label,onnx_score=peak,onnx=bool(peak>=.5),template=decide(td,margin,d,m))
            rows.append(row)
            print(json.dumps(row,ensure_ascii=False),flush=True)
        result={"scope":"synthetic only; held-out voices, rates and extra phrases","training_templates":len(training),"training_frames":len(y),"positive_total":sum(r["positive"] for r in rows),"negative_total":sum(not r["positive"] for r in rows)}
        for mode in ["onnx","template"]:
            result[mode]={"detected":sum(r[mode] and r["positive"] for r in rows),"false":sum(r[mode] and not r["positive"] for r in rows)}
        result["elapsed"]=round(time.monotonic()-start,2)
        (ROOT/"deka_experiment_report.json").write_text(json.dumps(dict(result,rows=rows),ensure_ascii=False,indent=2))
        print("REPORT",json.dumps(result,ensure_ascii=False),flush=True)
if __name__=="__main__":main()
