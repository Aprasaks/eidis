"""Synthetic-only preflight for model and short-utterance limitations."""
import pathlib,subprocess,tempfile,time,json
import numpy as np
from voice_id import VoiceID,centroid,similarity,ROOT,SR
VOICES=["Yuna","Eddy (한국어(한국))","Sandy (한국어(한국))"]
PHRASES=["오늘은 새로운 프로젝트를 시작하기 위해 준비하고 있습니다.",
         "데카, 지금 진행하고 있는 작업을 모두 보여 줘.",
         "내일은 일찍 일어나서 산책을 하고 싶어.",
         "데카"]
def synth(voice,phrase,rate,path):
    subprocess.run(["/usr/bin/say","-v",voice,"-r",str(rate),"-o",str(path),phrase],check=True,capture_output=True,timeout=20)
    data=subprocess.check_output(["/opt/homebrew/bin/ffmpeg","-v","error","-i",str(path),"-ac","1","-ar","16000","-f","s16le","-"],timeout=20)
    return np.frombuffer(data,dtype="<i2").copy()
def main():
    m=VoiceID()
    print("OFFLINE MODEL LOADED",flush=True)
    try:m.embed(np.zeros(SR*4,dtype=np.int16))
    except ValueError:print("PASS silence rejection",flush=True)
    else:raise AssertionError("silence accepted")
    samples={}
    with tempfile.TemporaryDirectory(prefix="deka-speaker-synthetic-") as d:
        for voice in VOICES:
            samples[voice]=[]
            for i,p in enumerate(PHRASES):
                pcm=synth(voice,p,175,pathlib.Path(d)/"synthetic.aiff")
                start=time.monotonic()
                try:
                    e=m.embed(pcm,min_seconds=.25 if i==3 else 1.)
                    samples[voice].append(e)
                    print(voice,i+1,"seconds",round(len(pcm)/SR,2),"infer_ms",round((time.monotonic()-start)*1000),flush=True)
                except ValueError:
                    if i!=3:raise
                    samples[voice].append(None)
    refs={v:centroid(e[:2]) for v,e in samples.items()}
    rows=[]
    for v,ref in refs.items():
        for test,e in samples.items():
            for idx,label in [(2,"sentence"),(3,"short")]:
                if e[idx] is not None:
                    rows.append(dict(enrolled=v,probe=test,kind=label,same=v==test,score=round(similarity(ref,e[idx]),4)))
    for r in rows:print(r,flush=True)
    for kind in ["sentence","short"]:
        same=[r["score"] for r in rows if r["kind"]==kind and r["same"]]
        other=[r["score"] for r in rows if r["kind"]==kind and not r["same"]]
        print(kind,"same",same,"different",other,flush=True)
    (ROOT/"synthetic-report.json").write_text(json.dumps({"scope":"synthetic voices, not human accuracy","rows":rows},ensure_ascii=False,indent=2))
if __name__=="__main__":main()
