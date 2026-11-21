"""Opt-in experimental personal keyword enrollment; raw audio held in RAM only.
No auto-start, wake integration, or voice authentication.
"""
import pathlib,time,json
import numpy as np
import sounddevice as sd
from sklearn.linear_model import LogisticRegression
from openwakeword.utils import AudioFeatures
from openwakeword.model import Model
from train_ko_prototype import inputs,trim,export
import train_ko_prototype as trainer
from benchmark import score

ROOT=pathlib.Path.home()/".jarvis-lab/wakeword"
DEST=ROOT/"jarvis_ko_personal_candidate.onnx"
RATE=16000
N=RATE*3
TRAIN_POS=["자비스"]*4+["자비스?"]*4
TRAIN_NEG=["서비스","자비","자비심","자바스크립트","오늘 날씨 알려줘","안녕하세요","지금 몇 시야","다시 시작해"]
TEST_POS=["자비스","자비스?","자비스 (조용하게)","자비스? (평소처럼)"]
TEST_NEG=["서비스","자비","자전거","오늘 뉴스 알려줘","안녕하세요","일반 문장 아무거나"]
def read_sample(phrase,index,total):
    while True:
        input(f"\n[{index}/{total}] '{phrase}' · Enter 누르면 3초 녹음 (Ctrl+C 취소)")
        print("지금 말씀하세요.",flush=True)
        try:
            data=sd.rec(N,samplerate=RATE,channels=1,dtype="int16",blocking=True).reshape(-1).copy()
        except sd.PortAudioError:
            raise SystemExit("마이크 입력 실패: macOS Terminal 권한 및 기본 마이크를 확인하세요.")
        trimmed=trim(data)
        if np.sqrt(np.mean(trimmed.astype(float)**2))<35 or len(trimmed)<1600:
            print("발화 확인 불가. 다시 녹음하세요.");continue
        if np.max(np.abs(data.astype(np.int32)))>=32760:
            print("입력이 잘렸을 수 있습니다. 조금 떨어져 다시 말하세요.");continue
        return trimmed

def main():
    print("JARVIS / 개인 호출어 보정 (실험)")
    print("학습 16회 + 분리 검증 10회. 음성 파일 저장·외부 전송 없음.")
    print("사용자가 동의하면 학습 가중치만 로컬에 저장합니다. 상시 감지 자동 활성화 없음.")
    if input("시작하려면 YES 입력: ").strip()!="YES":return
    features=AudioFeatures(inference_framework="onnx")
    train=[];test=[]
    total=len(TRAIN_POS)+len(TRAIN_NEG)+len(TEST_POS)+len(TEST_NEG)
    idx=0
    try:
        for phrase,label in [(p,1) for p in TRAIN_POS]+[(p,0) for p in TRAIN_NEG]:
            idx+=1;pcm=read_sample(phrase,idx,total);train.append((pcm,label))
        for phrase,label in [(p,1) for p in TEST_POS]+[(p,0) for p in TEST_NEG]:
            idx+=1;pcm=read_sample(phrase,idx,total);test.append((pcm,label))
        x=[];y=[]
        for pcm,label in train:
            for j in range(4):
                a,b=inputs(features,pcm,label,j>0);x.extend(a);y.extend(b)
        arr=np.asarray(x,dtype=np.float64)
        if not np.all(np.isfinite(arr)):raise SystemExit("비정상 특징 값, 학습 중단.")
        # Use liblinear to avoid high-dimensional LBFGS numerical issues.
        clf=LogisticRegression(C=.1,class_weight="balanced",max_iter=1000,random_state=21,solver="liblinear")
        clf.fit(arr,np.asarray(y))
        if not np.all(np.isfinite(clf.coef_)):raise SystemExit("비정상 가중치, 저장하지 않음.")
        trainer.DEST=DEST.with_name("jarvis_ko_personal_validation.onnx")
        export(clf,arr.shape[1])
        try:
            model=Model(wakeword_models=[str(trainer.DEST)],inference_framework="onnx")
            rows=[]
            for pcm,label in test:
                peak,_,_=score(model,pcm)
                rows.append((bool(label),peak))
                print("호출" if label else "비호출",f"점수 {peak:.3f}")
            tp=sum(p>=.5 for l,p in rows if l);fp=sum(p>=.5 for l,p in rows if not l)
            print(f"독립 발화 검증: 호출 {tp}/{len(TEST_POS)}, 비호출 오감지 {fp}/{len(TEST_NEG)}")
            if tp==len(TEST_POS) and fp==0:
                if input("후보 모델 가중치를 저장하려면 SAVE 입력: ").strip()=="SAVE":
                    trainer.DEST.replace(DEST)
                    DEST.chmod(0o600)
                    print("후보 저장 완료. 장시간 오감지 검증 전 자동 활성화 금지.")
            else: print("기준 미달. 후보 모델을 설치하지 않았습니다.")
        finally:
            trainer.DEST.unlink(missing_ok=True)
    except KeyboardInterrupt:
        print("\n사용자가 취소했습니다.")
    finally:
        train.clear();test.clear();sd.stop()
if __name__=="__main__":main()
