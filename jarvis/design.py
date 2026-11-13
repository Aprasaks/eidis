"""JARVIS design proposals.

Local mode is deterministic and never an LLM. Optional remote AI uses a fixed
OpenAI Responses endpoint only after BOTH process opt-in and per-request consent.
Output is a tightly validated palette/layout data structure, never executable CSS.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")
LAYOUTS = ("balanced", "focus", "panorama")
DENSITIES = ("airy", "normal", "compact")
ORBS = ("soft", "thin", "radiant")
API_ENDPOINT = "https://api.openai.com/v1/responses"

# Each family uses a safe dark surface and high-contrast foreground.
FAMILIES = (
    ("Obsidian", "#030508", "#a9c9dc", "#101a25", "#ecf3f8"),
    ("Cobalt", "#030a15", "#79baff", "#102039", "#edf6ff"),
    ("Iris", "#0b081b", "#b5a7fa", "#1c1738", "#f2f0ff"),
    ("Jade", "#04110f", "#8fdac7", "#122824", "#eafcf6"),
    ("Copper", "#130b09", "#efbc90", "#2b1c17", "#fff2e7"),
    ("Graphite", "#090b0e", "#c8d3de", "#1d232c", "#f4f7fa"),
)


class DesignError(ValueError):
    pass


class RemoteDesignError(RuntimeError):
    pass


def validate_prompt(prompt: str) -> str:
    if not isinstance(prompt, str):
        raise DesignError("디자인 요청은 문장이어야 합니다.")
    prompt = re.sub(r"\s+", " ", prompt).strip()
    if not 3 <= len(prompt) <= 320:
        raise DesignError("디자인 요청을 3~320자로 입력해 주세요.")
    return prompt


def remote_ready() -> bool:
    return (
        os.environ.get("JARVIS_ENABLE_DESIGN_API") == "1"
        and bool(os.environ.get("OPENAI_API_KEY", "").strip())
    )


def _luminance(value: str) -> float:
    rgb = [int(value[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    parts = [(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4) for v in rgb]
    return parts[0] * 0.2126 + parts[1] * 0.7152 + parts[2] * 0.0722


def contrast(first: str, second: str) -> float:
    a, b = sorted((_luminance(first), _luminance(second)), reverse=True)
    return (a + 0.05) / (b + 0.05)


def _validated_proposals(items: object, source: str) -> list[dict]:
    if not isinstance(items, list) or len(items) != 4:
        raise DesignError("시안은 정확히 네 개여야 합니다.")
    output: list[dict] = []
    for index, raw in enumerate(items, 1):
        if not isinstance(raw, dict):
            raise DesignError("시안 형식이 올바르지 않습니다.")
        allowed = {"title", "description", "background", "accent",
                   "surface", "foreground", "layout", "density", "orb"}
        if set(raw) != allowed:
            raise DesignError("허용되지 않은 디자인 속성이 있습니다.")
        title, desc = raw["title"], raw["description"]
        if not isinstance(title, str) or not 1 <= len(title.strip()) <= 28:
            raise DesignError("시안 이름이 올바르지 않습니다.")
        if not isinstance(desc, str) or not 1 <= len(desc.strip()) <= 100:
            raise DesignError("시안 설명이 올바르지 않습니다.")
        for token in ("background", "accent", "surface", "foreground"):
            if not isinstance(raw[token], str) or not HEX.fullmatch(raw[token]):
                raise DesignError("색상은 #RRGGBB 형식이어야 합니다.")
        if contrast(raw["background"], raw["foreground"]) < 7.0:
            raise DesignError("본문 텍스트 대비가 부족합니다.")
        if contrast(raw["background"], raw["accent"]) < 3.0:
            raise DesignError("강조색 대비가 부족합니다.")
        if raw["layout"] not in LAYOUTS or raw["density"] not in DENSITIES or raw["orb"] not in ORBS:
            raise DesignError("지원하지 않는 배치 설정입니다.")
        output.append({
            "id": f"{source}-{index}",
            "title": title.strip(), "description": desc.strip(),
            "background": raw["background"].lower(),
            "accent": raw["accent"].lower(),
            "surface": raw["surface"].lower(),
            "foreground": raw["foreground"].lower(),
            "layout": raw["layout"], "density": raw["density"], "orb": raw["orb"],
            "source": source,
        })
    return output


def local_suggestions(prompt: str) -> list[dict]:
    """A reproducible, actual token generator, not a model inference claim."""
    prompt = validate_prompt(prompt)
    lower = prompt.lower()
    # Requested color comes first; other options provide deliberate contrast.
    color_words = (
        (("보라", "violet", "purple", "은하", "galaxy"), 2),
        (("녹", "초록", "민트", "green", "mint"), 3),
        (("주황", "금", "따뜻", "warm", "amber"), 4),
        (("흑백", "무채", "회색", "mono", "graphite"), 5),
        (("파란", "블루", "blue", "청"), 1),
        (("어둡", "검정", "블랙", "dark", "black", "미니멀", "간결"), 0),
    )
    chosen = next((idx for words, idx in color_words if any(w in lower for w in words)), None)
    if chosen is None:
        chosen = int.from_bytes(hashlib.sha256(prompt.encode("utf-8")).digest()[:2], "big") % len(FAMILIES)
    order = [chosen] + [((chosen + offset) % len(FAMILIES)) for offset in (1, 3, 4)]
    compact = any(word in lower for word in ("빽빽", "밀도", "정보 많이", "compact", "좁게"))
    airy = any(word in lower for word in ("여백", "간결", "미니멀", "단순", "넓게", "airy"))
    dense = ["compact", "normal", "normal", "airy"] if compact else (
        ["airy", "airy", "normal", "compact"] if airy else ["normal", "airy", "compact", "normal"]
    )
    layouts = ["focus", "balanced", "panorama", "balanced"] if airy else ["balanced", "panorama", "focus", "balanced"]
    orbs = ["thin", "soft", "radiant", "soft"] if airy else ["soft", "radiant", "thin", "soft"]
    raw = []
    for i, idx in enumerate(order):
        name, bg, accent, surface, text = FAMILIES[idx]
        raw.append({
            "title": name,
            "description": ("여백과 집중을 강조한" if dense[i] == "airy" else
                            "정보와 흐름을 균형 있게 정리한" if dense[i] == "normal" else
                            "한 화면에 더 많은 상태를 담는") + " 로컬 시안",
            "background": bg, "accent": accent, "surface": surface, "foreground": text,
            "layout": layouts[i], "density": dense[i], "orb": orbs[i],
        })
    return _validated_proposals(raw, "rules")


def _schema() -> dict:
    properties = {
        "title": {"type": "string"},
        "description": {"type": "string"},
        "background": {"type": "string"},
        "accent": {"type": "string"},
        "surface": {"type": "string"},
        "foreground": {"type": "string"},
        "layout": {"type": "string", "enum": list(LAYOUTS)},
        "density": {"type": "string", "enum": list(DENSITIES)},
        "orb": {"type": "string", "enum": list(ORBS)},
    }
    return {
        "type": "object",
        "properties": {"proposals": {
            "type": "array", "items": {"type": "object", "properties": properties,
                                      "required": list(properties), "additionalProperties": False}
        }},
        "required": ["proposals"], "additionalProperties": False,
    }


def remote_suggestions(prompt: str, *, consent: bool) -> list[dict]:
    """Opt-in, single request to fixed trusted provider. No hidden retry/fallback."""
    prompt = validate_prompt(prompt)
    if not consent:
        raise DesignError("외부 AI 전송에 대한 이번 요청의 동의가 필요합니다.")
    if not remote_ready():
        raise DesignError("외부 AI가 비활성 상태입니다. 별도 API 키와 JARVIS_ENABLE_DESIGN_API=1 설정이 필요합니다.")
    model = os.environ.get("JARVIS_DESIGN_MODEL", "gpt-6-luna").strip()
    if not re.fullmatch(r"[A-Za-z0-9_.-]{2,64}", model):
        raise DesignError("설정한 모델 이름이 올바르지 않습니다.")
    payload = {
        "model": model,
        "store": False,
        "instructions": (
            "You are the JARVIS interface designer. Return exactly FOUR distinctly "
            "composed dark-mode interface designs. Output only the required JSON. "
            "All colors must be #RRGGBB, background should be dark; text contrast "
            "to background >=7:1 and accent contrast >=3:1. "
            "Preserve a circular orb; no HTML/CSS/code/URLs. "
            "Use short Korean descriptions."
        ),
        "input": [{"role": "user", "content": "Dashboard design request: " + prompt}],
        "max_output_tokens": 2200,
        "text": {"format": {
            "type": "json_schema", "name": "jarvis_design_proposals",
            "strict": True, "schema": _schema()
        }},
    }
    request = Request(
        API_ENDPOINT,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": "Bearer " + os.environ["OPENAI_API_KEY"].strip(),
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urlopen(request, timeout=24) as response:
            body = response.read(200_000)
    except (HTTPError, URLError, TimeoutError) as exc:
        # Never leak request body, headers or token into the UI.
        raise RemoteDesignError("외부 AI 설계 요청이 실패했습니다. API 설정·요금을 확인해 주세요.") from exc

    try:
        response = json.loads(body)
        texts = [
            content.get("text") for item in response.get("output", [])
            if item.get("type") == "message" for content in item.get("content", [])
            if content.get("type") == "output_text" and isinstance(content.get("text"), str)
        ]
        data = json.loads("".join(texts))
        return _validated_proposals(data["proposals"], "ai")
    except (ValueError, KeyError, TypeError, AttributeError) as exc:
        raise RemoteDesignError("AI 응답을 안전한 디자인 형식으로 검증하지 못했습니다.") from exc


def suggest_designs(prompt: str, *, provider: str = "rules", consent: bool = False) -> dict:
    if provider == "rules":
        items = local_suggestions(prompt)
    elif provider == "ai":
        items = remote_suggestions(prompt, consent=consent)
    else:
        raise DesignError("지원하지 않는 설계 방식입니다.")
    return {
        "provider": provider,
        "origin": "외부 AI 모델" if provider == "ai" else "로컬 규칙 기반",
        "proposals": items,
        "message": "AI 모델이 생성한 데이터 기반 시안입니다." if provider == "ai"
                   else "로컬 규칙을 조합해 새 디자인 설정을 만들었습니다. AI 생성은 아닙니다.",
    }
