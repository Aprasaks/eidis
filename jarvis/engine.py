"""Deterministic first slice. No pretend AI interpretation or remote actions."""
from __future__ import annotations

import re
from .storage import MemoryStore

CAPABILITIES = {
    "text_commands": "connected",
    "memory": "connected",
    "browser_voice": "browser_dependent",
    "browser_screen_preview": "permission_required",
    "vision_understanding": "not_connected",
    "llm_reasoning": "not_connected",
    "mac_control": "not_connected",
    "cloud": "not_connected",
    "iphone": "not_connected",
    "autonomous_tasks": "not_connected",
}


class JarvisEngine:
    def __init__(self, store: MemoryStore):
        self.store = store

    def handle(self, phrase: str) -> dict:
        if not isinstance(phrase, str):
            raise ValueError("문장 형식이 올바르지 않습니다.")
        phrase = re.sub(r"\s+", " ", phrase).strip()
        if not phrase or len(phrase) > 2000:
            raise ValueError("문장을 1~2000자로 입력해 주세요.")

        # Important: this MVP is a rule-based local prototype, NOT an LLM.
        clean = re.sub(r"^(자비스|jarvis)[,，?？!！.\s]*", "", phrase, flags=re.I).strip()
        if not clean:
            category, mode = "wake", "orb"
            response = "네, 듣고 있습니다."
        elif any(x in clean for x in ("대시보드 띄워", "대시보드 열어", "대시보드 보여", "작업 공간 열어")):
            category, mode = "open_dashboard", "dashboard"
            response = "작업 공간을 열었습니다. 현재 정보는 로컬 프로토타입 상태입니다."
        elif (any(x in clean for x in ("디자인 바꿔", "시안 보여", "대시보드 바꿔", "디자인 시안", "다른 디자인"))
              or ("대시보드" in clean and "바꿔" in clean)):
            category, mode = "design_options", "variants"
            response = "미리 준비한 레이아웃 세 가지를 보여드리겠습니다. AI가 새로 생성한 시안은 아닙니다."
        elif clean.startswith(("기억해 ", "기억해:", "기억해,", "기억해줘 ")):
            note = re.sub(r"^기억해(?:줘)?\s*[:,：]?\s*", "", clean).strip()
            if not note:
                raise ValueError("기억할 내용을 말해 주세요.")
            self.store.add_memory(note)
            category, mode = "remember", "memories"
            response = "말씀하신 내용을 로컬 기억에 저장했습니다."
        elif any(x in clean for x in ("기억 보여", "뭘 기억", "기억 목록", "저장한 기억")):
            category, mode = "recall", "memories"
            memories = self.store.recent_memories(1)
            response = ("가장 최근 기억은 '" + memories[0]["content"] + "'입니다.") if memories else "아직 저장된 기억이 없습니다."
        elif any(x in clean for x in ("화면 보여", "화면 봐", "내 화면", "스크린 공유", "화면 공유")):
            category, mode = "screen", "screen"
            response = "화면 미리보기는 사용자가 공유를 허용하면 볼 수 있습니다. 화면을 AI가 해석하는 기능은 아직 연결되지 않았습니다."
        elif any(x in clean for x in ("어디까지", "현재 상태", "진행 상황", "진행상황", "할 수 있어")):
            category, mode = "status", "dashboard"
            response = "로컬 명령과 명시적 기억 저장이 연결됐습니다. AI 판단, Mac 조작, 클라우드 연동은 아직 구현되지 않았습니다."
        else:
            category, mode = "unsupported", "orb"
            response = "이 명령을 처리할 AI 모델이나 실행 도구는 아직 연결되지 않았습니다. 실행한 것처럼 말씀드리지 않겠습니다."

        self.store.record_event(category, "handled" if category != "unsupported" else "unsupported")
        return {"spoken": response, "text": response, "mode": mode, "action": category,
                "executed": category not in ("unsupported", "screen", "design_options")}
