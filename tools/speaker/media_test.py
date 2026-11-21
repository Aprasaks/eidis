"""Explicit opt-in media-only follow-up. No owner rerecording or saved audio."""
import sounddevice as sd
from voice_id import VoiceID,load_profile
from calibrate import capture

def main():
    owner=load_profile()
    print("DEKA VOICE ID · 유튜브 음성만 검증")
    print("이어폰 없이 맥북 스피커로 다른 사람이 말하는 공개 영상을 재생하세요.")
    print("본인은 말하지 말고, 본인 녹음이나 사적인 통화는 사용하지 마세요.")
    print("각 6초 구간만 로컬에서 평가. 음성은 저장/전송하지 않습니다.")
    if input("동의하면 YES: ").strip()!="YES":return
    model=VoiceID()
    scores=[]
    for i in range(1,3):
        score=capture(model,owner,f"[영상 음성 {i}/2] 다른 사람이 말하는 영상", "sentence",6)
        if score is not None:
            scores.append(score)
            print(f"영상 음성 유사도 {score:.3f} · 실험 기준 0.52 {'이상' if score>=.52 else '미만'}",flush=True)
    print("영상 점수:",[round(s,3) for s in scores])
    print("실제 사용자 등록은 변경하지 않았습니다. 앱에는 아직 연결하지 않았습니다.")
if __name__=="__main__":
    try:main()
    except (KeyboardInterrupt,EOFError):print("\n사용자 종료")
    except (ValueError,sd.PortAudioError) as e:print("시험 중단:",str(e))
    finally:sd.stop()
