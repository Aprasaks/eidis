"""Explicit, time-limited live test. Never saves audio or activates JARVIS."""
import pathlib,queue,time
import numpy as np
import sounddevice as sd
from openwakeword.model import Model

ROOT=pathlib.Path.home()/".jarvis-lab/wakeword"
MODEL=ROOT/"jarvis_ko_experimental.onnx"
RATE=16000
CHUNK=1280
DURATION=45
THRESHOLD=.5

def main():
    personal=ROOT/"jarvis_ko_personal_candidate.onnx"
    chosen=personal if personal.is_file() else MODEL
    if not chosen.is_file():raise SystemExit("한국어 실험 모델이 아직 없습니다.")
    model=Model(wakeword_models=[str(chosen)], inference_framework="onnx")
    print("모델:",chosen.name)
    print("JARVIS / 한국어 호출어 검증 · 실험 모델")
    print("45초 동안만 마이크를 사용합니다. 음성 저장·외부 전송·자비스 실행 없음.")
    print("자비스라고 몇 번 말하고, 서비스/자비 및 일반 문장도 말해 보세요.")
    input("Enter를 누르면 검증 시작 (Ctrl+C 종료): ")
    q=queue.Queue(maxsize=16)
    overflow=[0]
    def capture(indata,frames,time_info,status):
        try:q.put_nowait((bytes(indata),str(status)))
        except queue.Full:overflow[0]+=1
    hits=0; peak=0.0; last=-10.0; prev=-10.0; dropped=0
    started=time.monotonic()
    try:
        with sd.RawInputStream(samplerate=RATE,blocksize=CHUNK,channels=1,dtype="int16",callback=capture):
            print("듣는 중…",flush=True)
            while time.monotonic()-started<DURATION:
                try:raw,status=q.get(timeout=.25)
                except queue.Empty:continue
                if status:dropped+=1
                p=float(max(model.predict(np.frombuffer(raw,dtype="<i2")).values()))
                peak=max(peak,p); t=time.monotonic()-started
                if p>=THRESHOLD and t-last>=1.5:
                    hits+=1;last=t
                    print(f"감지 {hits}회 · {t:.1f}초 · 점수 {p:.3f}",flush=True)
                if t-prev>=3:
                    print(f"경과 {t:.0f}초 / 45초 · 구간 최고점 {peak:.3f}",flush=True)
                    prev=t;peak=0.0
    except KeyboardInterrupt:
        print("사용자가 종료했습니다.")
    except sd.PortAudioError:
        raise SystemExit("마이크를 열 수 없습니다. macOS 개인정보 보호 및 보안 > 마이크에서 Terminal 권한과 기본 입력 장치를 확인하세요.")
    print(f"마이크 종료 · 감지 {hits}회 · 스트림 경고 {dropped}회 · 큐 손실 {overflow[0]}회")
    print("실제 발화 횟수와 비교하세요. 감지 횟수는 인식률이 아닙니다.")
if __name__=="__main__":main()
