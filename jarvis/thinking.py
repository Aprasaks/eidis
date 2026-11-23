"""Bounded, model-independent retrieval of explicitly stored DECHIVE context.

The output is evidence, NOT instructions to the assistant. No embeddings,
remote model, implicit recording or network activity is performed here.
"""
from __future__ import annotations

import re

STOPWORDS = frozenset({
    "자비스", "저기", "오늘", "어제", "내일", "우리", "그거", "이거",
    "이런", "저런", "대해서", "관련", "이야기", "생각", "이전에",
    "지난번", "예전에", "계속", "해줘", "알려줘", "어떻게",
    "왜", "했는데", "했던", "만들", "있는", "하는", "하자",
    "프로젝트", "고민", "조금", "그렇게", "뭐였지", "다시",
    "좀", "해봐", "뭐야", "같아", "있지", "했던거",
})
SUFFIXES = ("에서는", "으로는", "이라고", "이라서", "에서", "에게",
            "하고", "했던", "했지", "한테", "으로", "들은", "들이",
            "에는", "에", "은", "는", "을", "를", "이", "가", "도", "만", "랑")
MAX_CANDIDATES = 120
MAX_QUERY = 900


def tokens(text: str) -> tuple[str, ...]:
    """Small explainable lexical matcher: no costly model call per query."""
    words = []
    for raw in re.findall(r"[가-힣a-zA-Z0-9]{2,}", text.lower())[:80]:
        if raw not in STOPWORDS and raw not in words:
            words.append(raw)
        for suffix in SUFFIXES:
            if raw.endswith(suffix) and len(raw) - len(suffix) >= 2:
                stem = raw[:-len(suffix)]
                if stem not in STOPWORDS and stem not in words:
                    words.append(stem)
                break
    return tuple(words[:25])


def relevance(query_terms: tuple[str, ...], haystack: str) -> int:
    text = haystack.lower()
    return sum(min(3, len(term) // 3 + 1) for term in query_terms if term in text)


def compact(text: str, limit: int = 240) -> str:
    return " ".join(str(text).split())[:limit]


def related_context(store, query: str, limit: int = 5, *, include_thoughts: bool = True) -> list[dict]:
    """Return only positive, relevant matches from user's existing local data.

    The source kind and verification status stay attached so unverified AI
    artifacts can never silently become facts in the next conversation.
    """
    if not isinstance(query, str) or not 1 <= len(query.strip()) <= MAX_QUERY:
        raise ValueError("생각 맥락 질문은 1~900자여야 합니다.")
    if type(limit) is not int:
        raise ValueError("조회 개수가 잘못되었습니다.")
    limit = min(max(limit, 1), 6)
    terms = tokens(query)
    if not terms:
        return []
    candidates: list[dict] = []

    def propose(kind: str, item_id: int, title: str, body: str, status: str,
                when: str, weight: int = 0, *, global_preference: bool = False) -> None:
        score = relevance(terms, f"{title} {body}")
        if score <= 0 and not global_preference:
            return
        candidates.append({
            "kind": kind, "source_id": item_id,
            "title": compact(title, 100),
            "excerpt": compact(body, 260),
            "source_status": status,
            "recorded_at": when,
            "_score": score + weight,
        })

    # Only user-approved learned memories can affect model answers.
    # Candidate guesses and rejected memories are never retrieved.
    # Approved communication and value preferences stay relevant across topics.
    from .learning import LABELS
    global_ids = {
        row["id"] for row in store.db.execute(
            "SELECT id FROM learned_memories WHERE status='approved' "
            "AND category IN ('communication','values') ORDER BY id DESC LIMIT 2"
        )
    }
    for row in store.db.execute(
        "SELECT id,category,content,updated_at FROM learned_memories "
        "WHERE status='approved' ORDER BY id DESC LIMIT ?", (MAX_CANDIDATES,)
    ):
        propose("learned", row["id"], LABELS[row["category"]], row["content"],
                "user_approved", row["updated_at"], 3,
                global_preference=row["id"] in global_ids)

    for row in store.db.execute(
        "SELECT id,content,project,created_at FROM memories ORDER BY id DESC LIMIT ?",
        (MAX_CANDIDATES,)
    ):
        propose("memory", row["id"], row["project"], row["content"],
                "user_saved", row["created_at"], 1)

    for row in store.db.execute(
        "SELECT id,title,content,project,source_status,created_at FROM vault_items "
        "WHERE archived=0 ORDER BY id DESC LIMIT ?", (MAX_CANDIDATES,)
    ):
        propose("vault", row["id"], f"{row['project']} {row['title']}",
                row["content"], row["source_status"], row["created_at"])

    for row in store.db.execute(
        "SELECT id,name,goal,updated_at FROM projects ORDER BY id DESC LIMIT ?",
        (MAX_CANDIDATES,)
    ):
        tasks = store.db.execute(
            "SELECT title,status FROM project_tasks WHERE project_id=? ORDER BY id DESC LIMIT 12",
            (row["id"],)
        ).fetchall()
        task_summary = "; ".join(f"{r['title']} ({r['status']})" for r in tasks)
        propose("project", row["id"], row["name"],
                f"목표: {row['goal']}. 작업: {task_summary}",
                "local_project_record", row["updated_at"], 1)

    if include_thoughts:
        for row in store.db.execute(
            "SELECT id,topic,hypothesis,review_note,status,created_at "
            "FROM thought_records ORDER BY id DESC LIMIT ?", (MAX_CANDIDATES,)
        ):
            prose = f"{row['hypothesis']}. 검토: {row['review_note']}"
            propose("thought", row["id"], row["topic"], prose,
                    f"assistant_thought_{row['status']}", row["created_at"])

    # Higher lexical relevance first, then newer records within their source.
    candidates.sort(key=lambda item: (item["_score"], item["recorded_at"]), reverse=True)
    for item in candidates:
        item.pop("_score")
    return candidates[:limit]
