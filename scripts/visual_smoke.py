"""Real Chromium smoke/visual regression checks for JARVIS local web UI.

Run after starting app.py on localhost. Produces screenshots and machine-readable
browser/overflow/event reports. Screenshots are test data, not claimed to be
a screenshot of the user's Mac.
"""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

from playwright.sync_api import sync_playwright, expect

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = Path(os.environ.get("JARVIS_VISUAL_OUTPUT", str(ROOT / "artifacts" / "visual")))
URL = os.environ.get("JARVIS_BASE_URL", "http://127.0.0.1:8765")
CHROMIUM_EXECUTABLE = os.environ.get("JARVIS_CHROMIUM_PATH")
OUTPUT.mkdir(parents=True, exist_ok=True)
results = []
failures = []
browser_errors = []


def screenshot(page, label: str) -> None:
    path = OUTPUT / f"{label}.png"
    page.screenshot(path=str(path), full_page=True, animations="disabled")
    metrics = page.evaluate("""() => ({
      viewportWidth: innerWidth,
      docWidth: document.documentElement.scrollWidth,
      viewportHeight: innerHeight,
      docHeight: document.documentElement.scrollHeight,
      theme: Array.from(document.body.classList).find(x => x.startsWith('theme-')),
      dashboard: document.body.classList.contains('dashboard-open'),
      workspaceVisible: getComputedStyle(document.querySelector('#workspace')).display !== 'none'
    })""")
    results.append({"name": label, "file": path.name, **metrics})
    if metrics["docWidth"] > metrics["viewportWidth"] + 4:
        failures.append(f"{label}: horizontal overflow {metrics['docWidth']}px > {metrics['viewportWidth']}px")


def check_browser(page, size_name: str, viewport: dict) -> None:
    page.set_viewport_size(viewport)
    page.goto(URL, wait_until="networkidle")
    expect(page.locator("#hero-title")).to_have_text("무엇을 도와드릴까요?")
    expect(page.locator("#workspace")).to_be_hidden()
    expect(page.locator("#system-terminal")).to_be_visible()
    expect(page.locator("#terminal-content")).to_be_visible()
    assert page.locator(".topbar").count() == 0, "Idle view must not show branding/header"
    assert page.locator("#core-status").count() == 0, "No dashboard status counters"
    initial_terminal_size = page.locator("#system-terminal").bounding_box()
    assert initial_terminal_size["width"] <= 240, "Idle console should be tiny"
    assert initial_terminal_size["height"] <= 175, "Idle console should not dominate"
    page.locator("#terminal-toggle").click()
    expect(page.locator("body")).to_have_class(__import__("re").compile(r".*terminal-expanded.*"))
    screenshot(page, f"{size_name}_11_terminal_expanded")
    page.locator("#terminal-toggle").click()
    expect(page.locator("body")).not_to_have_class(__import__("re").compile(r".*terminal-expanded.*"))
    screenshot(page, f"{size_name}_01_idle")

    page.get_by_role("button", name="자비스 호출").click()
    expect(page.locator("body")).to_have_class(__import__("re").compile(r".*awakened.*"))
    page.wait_for_timeout(2300)
    screenshot(page, f"{size_name}_02_summoned")

    page.get_by_role("button", name="작업 공간 열기").click()
    expect(page.locator("#workspace")).to_be_visible()
    expect(page.locator("#dashboard-view")).to_be_visible()
    expect(page.locator(".quiet-workspace")).to_be_visible()
    expect(page.locator(".workspace-shortcut")).to_have_count(3)
    if size_name == "desktop":
        expect(page.locator("#terminal-feed")).to_contain_text("작업 공간")
    assert page.locator("#activity-feed").count() == 0, "Scattered dashboard logs must be removed"
    page.wait_for_timeout(650)
    screenshot(page, f"{size_name}_03_dashboard")
    if size_name == "desktop":
        dashboard_fold = page.evaluate("""() => {
          const dock = document.querySelector('.command-dock').getBoundingClientRect();
          const tools = ['show-memory', 'open-screen'].map(id =>
            document.getElementById(id).getBoundingClientRect()
          );
          return tools.every(rect => rect.bottom > 0 && rect.bottom < dock.top - 6);
        }""")
        assert dashboard_fold, "Dashboard quick actions should be visible above command dock"

    page.locator("#show-variants").click()
    expect(page.locator("#variants-view")).to_be_visible()
    expect(page.locator(".variant")).to_have_count(4)
    screenshot(page, f"{size_name}_04_design_gallery")
    # The design studio must remain reachable; visual layout can scroll inside
    # the on-demand workspace without colliding with the fixed input dock.
    if size_name == "desktop":
        expect(page.locator('[data-theme="ambient"]')).to_be_visible()
        expect(page.locator('#apply-design')).to_be_attached()

    # Preview must change the theme but not modify persistent memory.
    page.get_by_role("button", name="Polar 시안 미리보기").click()
    expect(page.locator("body")).to_have_class(__import__("re").compile(r".*theme-polar.*"))
    expect(page.locator('[data-theme="polar"]')).to_have_attribute("aria-pressed", "true")
    screenshot(page, f"{size_name}_05_polar_preview")

    # Cancel must go back to previous theme (Nebula in fresh session).
    page.get_by_role("button", name="이전 화면으로").click()
    expect(page.locator("body")).to_have_class(__import__("re").compile(r".*theme-nebula.*"))
    expect(page.locator("#dashboard-view")).to_be_visible()

    page.locator("#show-variants").click()
    page.get_by_role("button", name="Studio 시안 미리보기").click()
    page.get_by_role("button", name="선택한 디자인 적용").click()
    expect(page.locator("body")).to_have_class(__import__("re").compile(r".*theme-studio.*"))
    expect(page.locator("#dashboard-view")).to_be_visible()
    screenshot(page, f"{size_name}_06_studio_applied")

    page.locator("#show-memory").click()
    expect(page.locator("#memories-view")).to_be_visible()
    screenshot(page, f"{size_name}_07_memories")
    page.get_by_role("button", name="작업 공간으로").click()

    # Vision controls must be present, but no request may be issued without
    # a separate consent and a user-chosen live screen.
    page.locator("#open-screen").click()
    expect(page.locator("#screen-view")).to_be_visible()
    requests = []
    page.on("request", lambda req: requests.append(req.url) if "/api/vision/analyze" in req.url else None)
    expect(page.locator("#vision-consent")).not_to_be_checked()
    page.get_by_role("button", name="AI로 현재 화면 한 장 분석").click()
    expect(page.locator("#vision-status")).to_contain_text("먼저 화면 공유")
    assert not requests, "Vision API must never be invoked before screen selection/consent"
    screenshot(page, f"{size_name}_10_vision_off")
    page.get_by_role("button", name="작업 공간으로").click()

    # Existing input command should keep working after transitions.
    page.locator("#command-input").fill("자비스 대시보드 좀 바꿔")
    page.locator("#command-form button[type=submit]").click()
    expect(page.locator("#variants-view")).to_be_visible()
    page.get_by_role("button", name="이전 화면으로").click()

    # A user-authored request should create four NEW palettes, not just select a preset.
    page.locator("#show-variants").click()
    page.locator("#design-request summary").click()
    page.locator("#design-prompt").fill("더 어둡고 간결하게, 여백을 넓혀")
    page.get_by_role("button", name="새 시안 4개 만들기").click()
    expect(page.locator("#generated-variant-list .generated-variant")).to_have_count(4)
    expect(page.locator("#design-origin")).to_contain_text("LOCAL RULES")
    page.locator("#generated-variant-list .generated-variant").first.click()
    expect(page.locator("body")).to_have_class(__import__("re").compile(r".*theme-generated.*"))
    screenshot(page, f"{size_name}_08_generated_preview")
    page.get_by_role("button", name="이전 화면으로").click()
    expect(page.locator("body")).to_have_class(__import__("re").compile(r".*theme-studio.*"))

    # Natural-language command should trigger local token generation automatically.
    page.locator("#command-input").fill("자비스 대시보드 더 어둡고 간결하게 바꿔")
    page.locator("#command-form button[type=submit]").click()
    expect(page.locator("#variants-view")).to_be_visible()
    expect(page.locator("#design-request-status")).to_contain_text("로컬 규칙을")
    expect(page.locator("#design-prompt")).to_have_value("대시보드 더 어둡고 간결하게 바꿔")
    expect(page.locator("#generated-variant-list .generated-variant")).to_have_count(4)
    expect(page.locator("#design-request")).not_to_have_attribute("open", "")
    screenshot(page, f"{size_name}_09_voice_style_request")
    page.get_by_role("button", name="이전 화면으로").click()

    # All operational history lives in the single console.
    if size_name == "desktop":
        page.locator("#terminal-toggle").click()
        page.locator('[data-terminal-filter="action"]').click()
        expect(page.locator("#terminal-feed")).to_contain_text("작업 공간")
        page.locator('[data-terminal-filter="error"]').click()
        expect(page.locator("#terminal-feed")).to_contain_text("오류 없음")
        page.locator('[data-terminal-filter="all"]').click()
        screenshot(page, f"{size_name}_11_unified_terminal")
        page.locator("#terminal-clear").click()
        expect(page.locator("#terminal-feed")).to_contain_text("› _")
        # Clear means UI-only. The SQLite activity is not erased.
        activity = page.evaluate("""async () => (await (await fetch('/api/activity')).json()).items""")
        assert len(activity) > 0, "Terminal clear must never delete server activity"
        page.locator("#terminal-toggle").click()

    # Presence state should remain available.
    # Closing by voice-style text command must return to the quiet idle screen.
    page.locator("#command-input").fill("자비스 대시보드 닫아")
    page.locator("#command-form button[type=submit]").click()
    expect(page.locator("#workspace")).to_be_hidden()
    expect(page.locator("#hero-title")).to_have_text("무엇을 도와드릴까요?")
    screenshot(page, f"{size_name}_12_back_to_idle")


def run() -> int:
    with sync_playwright() as playwright:
        launch = {"headless": True, "args": ["--no-sandbox"]}
        if CHROMIUM_EXECUTABLE:
            launch["executable_path"] = CHROMIUM_EXECUTABLE
        browser = playwright.chromium.launch(**launch)
        try:
            for name, viewport in (
                ("desktop", {"width": 1440, "height": 900}),
                ("mobile", {"width": 390, "height": 844}),
            ):
                context = browser.new_context(viewport=viewport, locale="ko-KR", reduced_motion="reduce")
                page = context.new_page()
                page.on("pageerror", lambda error: browser_errors.append(str(error)))
                try:
                    check_browser(page, name, viewport)
                    print(f"PASS {name} visual/interaction smoke")
                except Exception as exc:
                    failures.append(f"{name}: {exc}")
                    screenshot(page, f"{name}_ERROR_state")
                    print(f"FAIL {name}: {exc}", file=sys.stderr)
                finally:
                    context.close()
        finally:
            browser.close()

    report = {
        "url": URL, "recorded_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "screenshots": results, "failures": failures,
        "page_errors": browser_errors,
        "note": "Local Chromium test of this commit; not a live Mac screenshot or AI-generated design."
    }
    (OUTPUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    if browser_errors:
        failures.extend(f"JavaScript exception: {err}" for err in browser_errors)
    print(f"Saved {len(results)} screenshots to {OUTPUT}")
    for error in failures:
        print("ERROR:", error, file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(run())
