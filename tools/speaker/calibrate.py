"""Compare genuine and non-owner scores, with explicit per-capture consent.
No microphone audio, external transmission, or new biometric vectors on disk.
No production threshold is automatically selected.
"""
import pathlib,tempfile
import numpy as np
import sounddevice as sd
from voice_id import VoiceID,load_profile,similarity,SR
from benchmark import synth,VOICES

def synthetic_probes(model,owner):
    rows=[]
    with tempfile.TemporaryDirectory(prefix="deka-speaker-negative-") as d:
        for voice in VOICES:
            for kind,phrase,minimum in [("short","데카",.25),("sentence","데카, 오늘 할 일을 알려줘.",1.)]:
                pcm=synth(voice,phrase,175,pathlib.Path(d)/"fixture.aiff")
                try: score=similarity(owner,model.embed(pcm,min_seconds=minimum))
                except ValueError:
                    print(voice,kind,"음성 부족 · 판정 보류",flush=True);continue
                rows.append((kind,score))
                print(f"{voice} / {kind}: {score:.3f}",flush=True)
    return rows

def capture(model,owner,label,kind,seconds):
    input("\n"+label+"\nEnter를 누른 후 말하거나 재생하세요. ")
    print(f"지금 · {seconds}초",flush=True)
    pcm=sd.rec(SR*seconds,samplerate=SR,channels=1,dtype="int16",blocking=True).reshape(-1)
    try:
        return similarity(owner,model.embed(pcm,min_seconds=.25 if kind=="short" else 1.5))
    except ValueError:
        print("음성 부족/입력 품질 문제 · 판정 보류",flush=True)
        return None
    finally:del pcm

def main():
    owner=load_profile()
    model=VoiceID()
    print("DEKA VOICE ID · 등록된 특징의 독립 검증",flush=True)
    print("내 목소리와 다른 합성 목소리 비교 (마이크 사용 없음)",flush=True)
    negatives=synthetic_probes(model,owner)
    print("\n실제 목소리 테스트: 짧은 호출 3회, 문장 1회, 유튜브 음성 2회.")
    print("녹음은 각 구간에만 사용하고 즉시 폐기합니다. 등록된 특징은 변경하지 않습니다.")
    if input("마이크 시험에 동의하면 YES: ").strip()!="YES":return
    owner_rows=[]
    media_rows=[]
    for label,kind,seconds in [
        ("[내 목소리 1/4] 데카 (평소 말투)","short",3),
        ("[내 목소리 2/4] 데카? (조금 작은 목소리)","short",3),
        ("[내 목소리 3/4] 데카 (평소보다 조금 멀리)","short",3),
        ("[내 목소리 4/4] 오늘 날씨를 알려줘. 잠시 나갔다 올게.","sentence",6)]:
        s=capture(model,owner,label,kind,seconds)
        if s is not None:
            owner_rows.append((kind,s))
            print(f"내 목소리 유사도 {s:.3f}",flush=True)
    print("\n이제 유튜브에서 다른 사람이 한국어로 말하는 영상만 재생하세요. 본인은 말하지 마세요.")
    print("맥북 스피커로 재생, 평소 듣는 음량. 본인 녹음/사적인 통화는 사용하지 마세요.")
    if input("영상 음성 시험을 시작하면 YES (건너뛰려면 Enter): ").strip()=="YES":
        for i in range(1,3):
            s=capture(model,owner,f"[영상 음성 {i}/2] 영상 속 말소리만", "sentence",6)
            if s is not None:
                media_rows.append(("sentence",s))
                print(f"영상 음성 유사도 {s:.3f}",flush=True)
    print("\n=== 결과 (유사도, 성공률 아님) ===")
    for kind in ["short","sentence"]:
        genuine=[s for k,s in owner_rows if k==kind]
        others=[s for k,s in negatives+media_rows if k==kind]
        print(f"{kind}: 내 목소리 {[round(s,3) for s in genuine]} / 다른 음성 {[round(s,3) for s in others]}")
        if genuine and others:
            print(f"관측 점수 간격: {min(genuine)-max(others):+.3f}")
    print("이번 시험은 보정 후보 확인용이며 보안 인증이나 정확도 보장이 아닙니다.")
    print("기존 등록 그대로 유지 · 자동 앱 연결 없음 · 녹음 파일 없음")
if __name__=="__main__":
    try:main()
    except (KeyboardInterrupt,EOFError):print("\n사용자 종료")
    except (ValueError,sd.PortAudioError) as e:print("시험 중단:",str(e))
    finally:sd.stop()
