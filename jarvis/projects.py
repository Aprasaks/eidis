"""Explicit read-only GitHub verification of public repositories.

All network calls are initiated by a user clicking "GitHub 확인".
No secret tokens, remote writes, scheduled checks, redirects or arbitrary URLs.
A green workflow is never treated as proof that a user task is complete.
"""
from __future__ import annotations

import json
import re
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urlsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler

API_ROOT = "https://api.github.com"
MAX_RESP_BYTES = 180_000


class ProjectCheckError(RuntimeError):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def validate_repo(value: object, *, allow_empty: bool = False) -> str:
    if not isinstance(value, str):
        raise ValueError("GitHub 저장소는 owner/repo 형식이어야 합니다.")
    value = value.strip()
    if allow_empty and not value:
        return ""
    if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})/[A-Za-z0-9_.-]{1,100}", value):
        raise ValueError("GitHub 저장소는 owner/repo 형식이어야 합니다.")
    if value.split("/")[1] in (".", ".."):
        raise ValueError("GitHub 저장소 이름이 올바르지 않습니다.")
    return value


def _read_public_api(path: str) -> dict:
    # Never build URLs from user input except validated owner/repo segments.
    url = API_ROOT + path
    parsed = urlsplit(url)
    if parsed.scheme != "https" or parsed.netloc != "api.github.com":
        raise ProjectCheckError("허용되지 않은 외부 주소입니다.")
    request = Request(url, headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "jarvis-project-readonly/1.3",
        "X-GitHub-Api-Version": "2022-11-28",
    })
    try:
        with build_opener(NoRedirect()).open(request, timeout=8) as response:
            body = response.read(MAX_RESP_BYTES + 1)
    except (HTTPError, URLError, TimeoutError, OSError) as exc:
        raise ProjectCheckError(
            "GitHub 공개 API에서 확인하지 못했습니다. 공개 저장소와 네트워크·요청 제한을 확인해 주세요."
        ) from exc
    if len(body) > MAX_RESP_BYTES:
        raise ProjectCheckError("GitHub 응답이 허용 크기를 초과했습니다.")
    try:
        result = json.loads(body)
        if not isinstance(result, dict):
            raise ValueError("not object")
        return result
    except (ValueError, TypeError) as exc:
        raise ProjectCheckError("GitHub 응답의 형식이 올바르지 않습니다.") from exc


def verify_public_github(repo: object) -> dict:
    """Create a source-bounded observation; never mutate a project task."""
    name = validate_repo(repo)
    segments = "/".join(quote(part, safe="") for part in name.split("/"))
    info = _read_public_api("/repos/" + segments)
    actual = info.get("full_name")
    if not isinstance(actual, str) or actual.casefold() != name.casefold():
        raise ProjectCheckError("요청한 저장소와 GitHub 응답이 일치하지 않습니다.")
    if info.get("private") is not False:
        raise ProjectCheckError("공개 저장소에서만 읽기 전용 확인을 지원합니다.")
    branch = info.get("default_branch")
    if not isinstance(branch, str) or not 1 <= len(branch) <= 120:
        raise ProjectCheckError("기본 브랜치를 확인하지 못했습니다.")
    branch_info = _read_public_api("/repos/" + segments + "/branches/" + quote(branch, safe=""))
    sha = (branch_info.get("commit") or {}).get("sha")
    if not isinstance(sha, str) or not re.fullmatch(r"[0-9a-fA-F]{40}", sha):
        raise ProjectCheckError("브랜치의 커밋 해시를 확인하지 못했습니다.")
    runs = _read_public_api(
        "/repos/" + segments + "/actions/runs?" + urlencode({"branch":branch,"per_page":10})
    ).get("workflow_runs")
    if not isinstance(runs, list):
        raise ProjectCheckError("Workflow 확인 응답이 올바르지 않습니다.")
    # A success on an older commit is not a success for the current head.
    matching = next((run for run in runs
                     if isinstance(run, dict) and run.get("head_sha") == sha), None)
    state = "unavailable"
    conclusion = "unknown"
    url = ""
    if matching:
        state = str(matching.get("status") or "unknown")[:40]
        conclusion = str(matching.get("conclusion") or "pending")[:40]
        candidate = matching.get("html_url", "")
        if isinstance(candidate, str):
            parsed = urlsplit(candidate)
            if parsed.scheme == "https" and parsed.netloc == "github.com":
                url = candidate[:500]
    return {
        "provider": "github",
        "repository": name,
        "branch": branch,
        "head_sha": sha.lower(),
        "workflow_state": state,
        "workflow_conclusion": conclusion,
        "workflow_url": url,
    }
