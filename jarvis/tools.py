"""Permission-gated tool runner for the independent JARVIS app.

Only a single read-only tool is enabled in v1.4. The model cannot synthesize
tool names, arguments, shell commands or approvals. Explicit user intent is
necessary, and every attempt has a durable, provenance-limited receipt.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from urllib.parse import urlsplit

from .projects import ProjectCheckError, verify_public_github
from .storage import MemoryStore

MAX_CHECKS_PER_PROCESS = 8


@dataclass(frozen=True)
class ToolSpec:
    name: str
    permission: str
    effect: str
    requires_user_request: bool

    def public(self) -> dict:
        return {
            "name": self.name, "permission": self.permission,
            "effect": self.effect,
            "requires_user_request": self.requires_user_request,
            "enabled": True,
        }


ENABLED_TOOLS = {
    "github.public_verify": ToolSpec(
        "github.public_verify", "read_external", "read_only", True
    ),
}


class ToolDenied(ValueError):
    pass


class ToolExecutionError(RuntimeError):
    pass


class ToolRunner:
    def __init__(self, store: MemoryStore):
        self.store = store
        self.attempts = 0

    def manifest(self) -> dict:
        return {
            "tools": [spec.public() for spec in ENABLED_TOOLS.values()],
            "remaining": max(0, MAX_CHECKS_PER_PROCESS - self.attempts),
            "write_tools_enabled": False,
            "note": "공개 GitHub 읽기만 지원합니다. 파일 수정·배포·삭제 도구는 연결하지 않았습니다.",
        }

    @staticmethod
    def _validate_evidence(result: object, repo: str) -> dict:
        if not isinstance(result, dict) or not isinstance(result.get("repository"), str) or (
            result["repository"].casefold() != repo.casefold()
        ):
            raise ToolExecutionError("GitHub 확인 결과가 요청한 저장소와 다릅니다.")
        branch, sha = result.get("branch"), result.get("head_sha")
        if not isinstance(branch, str) or not 1 <= len(branch) <= 120:
            raise ToolExecutionError("기본 브랜치 증거가 올바르지 않습니다.")
        if not isinstance(sha, str) or not re.fullmatch(r"[0-9a-fA-F]{40}", sha):
            raise ToolExecutionError("커밋 검증 자료가 올바르지 않습니다.")
        state = result.get("workflow_state")
        conclusion = result.get("workflow_conclusion")
        if state not in ("completed", "queued", "in_progress", "requested",
                         "waiting", "pending", "unavailable", "unknown"):
            raise ToolExecutionError("Workflow 상태를 신뢰할 수 없습니다.")
        if conclusion not in ("success", "failure", "cancelled", "timed_out",
                              "skipped", "action_required", "neutral",
                              "unknown", "pending", "startup_failure", "stale"):
            raise ToolExecutionError("Workflow 결론 형식이 올바르지 않습니다.")
        # The verifier deliberately leaves the URL empty if no run for this SHA.
        url = result.get("workflow_url")
        if not isinstance(url, str) or len(url) > 500:
            raise ToolExecutionError("Workflow 링크가 올바르지 않습니다.")
        if url:
            parts = urlsplit(url)
            if parts.scheme != "https" or parts.netloc != "github.com" or (
                not parts.path.casefold().startswith("/" + repo.casefold() + "/actions/runs/")
            ):
                raise ToolExecutionError("검증된 저장소의 GitHub Workflow 링크가 아닙니다.")
        if state == "unavailable" and (conclusion != "unknown" or url):
            raise ToolExecutionError("확인되지 않은 Workflow를 확인된 결과로 처리할 수 없습니다.")
        return result

    def execute(self, name: str, project_id: int, *, explicit_request: bool = False,
                inspector=None) -> dict:
        spec = ENABLED_TOOLS.get(name)
        if spec is None:
            raise ToolDenied("허용되지 않은 도구입니다. 파일 수정·배포는 실행할 수 없습니다.")
        if spec.requires_user_request and explicit_request is not True:
            raise ToolDenied("외부 조회는 사용자의 명시적 요청이 있을 때만 실행합니다.")
        project = self.store._project_row(project_id)
        repo = project["repo_full_name"]
        if not repo:
            raise ToolDenied("GitHub 저장소를 연결한 프로젝트가 아닙니다.")
        if self.attempts >= MAX_CHECKS_PER_PROCESS:
            raise ToolDenied("이 실행 세션의 GitHub 확인 횟수 제한에 도달했습니다.")
        run_id = self.store.start_tool_execution(spec.name, project["id"], spec.permission)
        self.attempts += 1
        try:
            check = self._validate_evidence(
                (inspector or verify_public_github)(repo), repo
            )
            checked_project = self.store.save_project_check(project["id"], check)
            outcome = (
                "head_observed" if check["workflow_state"] == "unavailable"
                else "head_and_workflow_observed"
            )
            receipt = self.store.finish_tool_execution(
                run_id, "completed", outcome, check["head_sha"]
            )
            self.store.record_event("tool_github_check", outcome)
            return {"project": checked_project, "receipt": receipt}
        except Exception as exc:
            outcome = "invalid_evidence" if isinstance(exc, ToolExecutionError) else "provider_unavailable"
            self.store.finish_tool_execution(run_id, "failed", outcome)
            self.store.record_event("tool_github_check_failed", outcome)
            if isinstance(exc, ToolExecutionError):
                raise
            # Never expose URL/request internals or raw source payload to the user.
            raise ToolExecutionError("GitHub 공개 저장소 확인에 실패했습니다. 공개 여부·연결 상태를 확인해 주세요.") from exc
