"""Explicit guided DEKA test; no training, storage, or app activation."""
import pathlib
import numpy as np
import sounddevice as sd
from openwakeword.model import Model
from benchmark import score
from train_ko_prototype import trim

ROOT=pathlib.Path.home()/".jarvis-lab/wakeword"
MODEL=ROOT/"deka_ko_experimental.onnx"
TRIALS=[("데카",True),("데카?",True),("내가",False),("네가",False),
        ("데카 (작은 목소리)",True),("데이터",False),("데카 (평소처럼)",True),("오늘 날씨 어때",False)]

def main():
    if not MODEL.is_file():raise SystemExit("데카 실험 모델 없음.")
    model=Model(wakeword_models=[str(MODEL)],inference_framework="onnx")
    print("DEKA / 호출어 검증 (8회, 학습 아님)")
    print("각 발화 3초만 녹음 · 메모리에서 평가 후 폐기 · 외부 전송 없음.")
    print("호출 감지 기준 0.5 · 자비스 앱 활성화 없음.")
    if input("준비되면 YES 입력: ").strip()!="YES":return
    rows=[]
    try:
        for i,(phrase,label) in enumerate(TRIALS,1):
            while True:
                input(f"\n[{i}/{len(TRIALS)}] '{phrase}' → Enter")
                print("지금 말씀하세요.",flush=True)
                pcm=sd.rec(48000,samplerate=16000,channels=1,dtype="int16",blocking=True).reshape(-1)
                sample=trim(pcm)
                if len(sample)<1600 or np.sqrt(np.mean(sample.astype(float)**2))<35:
                    print("말소리가 작습니다. 다시 시도하세요.");continue
                peak,_,_=score(model,sample)
                del pcm,sample
                hit=peak>=.5
                rows.append((label,hit))
                print(f"점수 {peak:.3f} · {'감지' if hit else '미감지'} · {'정상' if hit==label else '실패'}",flush=True)
                break
        print(f"호출 성공 {sum(a and b for a,b in rows)}/4 · 비호출 오감지 {sum(not a and b for a,b in rows)}/4")
        print("짧은 실험 결과이며 상시 감지 설치 기준은 아닙니다.")
    except KeyboardInterrupt:print("사용자 종료")
    except sd.PortAudioError:print("마이크 입력 실패 · Terminal 권한 또는 마이크 확인")
    finally:sd.stop()
if __name__=="__main__":main()
