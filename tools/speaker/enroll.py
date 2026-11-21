"""User-consented local lab. Save only a provisional centroid, never recording."""
import os,sys,time
import numpy as np
import sounddevice as sd
from voice_id import VoiceID,centroid,similarity,PROFILE,REVISION,SR

PROMPTS=[
"데카, 오늘 내가 해야 할 일을 알려줘.",
"지금 군산 날씨는 어때? 잠깐 밖에 나갔다 올게.",
"오늘 진행 중인 프로젝트를 한번 살펴보고 싶어.",
"데카, 잠시 기다려 줘. 먼저 이 작업을 마무리할게.",
"내일은 조금 일찍 일어나서 새로운 계획을 세울 거야.",
"지금은 편하게 이야기하고 싶어. 오늘은 어땠어?"]
HOLDOUT=["데카, 오늘 뉴스 중 중요한 내용을 알려줘.","지금은 커피를 마시면서 책을 읽고 있어.","데카, 나중에 다시 이야기하자. 잠시 쉬고 싶어."]
def record(label):
    input("\n"+label+"\nEnter를 누르고 말하세요. ")
    print("말씀하세요 · 6초",flush=True)
    pcm=sd.rec(6*SR,samplerate=SR,channels=1,dtype="int16",blocking=True).reshape(-1)
    return pcm

def capture(model,label):
    for _ in range(3):
        pcm=record(label)
        try: return model.embed(pcm)
        except ValueError:print("음성이 충분하지 않거나 너무 크게 녹음됐어요. 다시 시도해 주세요.")
        finally: del pcm
    raise ValueError("capture quality")

def main():
    if PROFILE.exists():
        print("등록된 실험용 프로필이 있습니다. 기존 등록을 덮어쓰지 않습니다.")
        return
    print("DEKA VOICE ID · 로컬 화자 인증 실험")
    print("유튜브/음악과 자비스를 끈 조용한 상태에서 진행하세요.")
    print("등록 6문장 + 독립 검증 3문장. 각 6초. 원본 녹음은 메모리에서 처리하고 파일로 저장하거나 전송하지 않습니다.")
    print("음성 특징은 개인을 구별하는 민감한 정보입니다. SAVE 전에는 파일이 생성되지 않습니다.")
    print("이 모델은 녹음 재생이나 다른 사람을 완벽히 구별하지 못합니다.")
    if input("동의하고 시작하려면 YES: ").strip()!="YES":return
    model=VoiceID()
    training=[capture(model,f"[등록 {i}/6] {p}") for i,p in enumerate(PROMPTS,1)]
    c=centroid(training)
    for i,p in enumerate(HOLDOUT,1):
        e=capture(model,f"[검증 {i}/3] {p}")
        score=similarity(c,e)
        print(f"유사도 {score:.3f} (확률 아님)",flush=True)
    print("자기 목소리 검증만 완료. 다른 화자/유튜브 오수락 검증은 별도 필요.")
    if input("실험용 음성 특징만 저장하려면 SAVE: ").strip()!="SAVE":return
    old=os.umask(0o077)
    try:
        with PROFILE.open("xb") as f:np.savez(f,embedding=c,revision=REVISION)
    finally:os.umask(old)
    print("실험용 프로필 저장 완료. 자비스 앱에는 아직 연결하지 않았습니다.")
    print("삭제 경로:",PROFILE)
if __name__=="__main__":
    try:main()
    except (KeyboardInterrupt,EOFError):print("\n사용자가 종료했습니다.")
    except (ValueError,sd.PortAudioError) as e:print("등록 중단:",str(e))
    finally:sd.stop()
