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
    expect(page.locator("#hero-title")).to_have_text("부르면, 연결됩니다.")
    expect(page.locator("#workspace")).to_be_hidden()
    screenshot(page, f"{size_name}_01_idle")

    page.get_by_role("button", name="자비스 호출").click()
    expect(page.locator("body")).to_have_class(__import__("re").compile(r".*awakened.*"))
    page.wait_for_timeout(2300)
    screenshot(page, f"{size_name}_02_summoned")

    page.get_by_role("button", name="작업 공간 열기").click()
    expect(page.locator("#workspace")).to_be_visible()
    expect(page.locator("#dashboard-view")).to_be_visible()
    expect(page.locator("#core-status")).to_have_text("연결됨")
    expect(page.locator("#memory-count")).not_to_have_text("—")
    page.wait_for_timeout(650)
    screenshot(page, f"{size_name}_03_dashboard")

    page.get_by_role("button", name="화면 다시 설계").click()
    expect(page.locator("#variants-view")).to_be_visible()
    expect(page.locator(".variant")).to_have_count(4)
    screenshot(page, f"{size_name}_04_design_gallery")
    if size_name == "desktop":
        # The reason for this redesign: all four studies and the apply action
        # must be visible together, without requiring an initial scroll.
        first_fold = page.evaluate("""() => {
          const action = document.querySelector('#apply-design').getBoundingClientRect();
          const dock = document.querySelector('.command-dock').getBoundingClientRect();
          const previews = [...document.querySelectorAll('.variant')].map(
            el => el.getBoundingClientRect()
          );
          return {
            buttonVisible: action.bottom > 0 && action.bottom < dock.top - 6,
            studiesVisible: previews.every(rect => rect.bottom < dock.top - 6),
            columns: new Set(previews.map(rect => Math.round(rect.left))).size
          };
        }""")
        assert first_fold["buttonVisible"], f"Apply action is hidden below the desktop fold: {first_fold}"
        assert first_fold["studiesVisible"], f"Some design studies are hidden below the dock: {first_fold}"
        assert first_fold["columns"] == 4, f"All four studies should sit side-by-side: {first_fold}"

    # Preview must change the theme but not modify persistent memory.
    page.get_by_role("button", name="Polar 시안 미리보기").click()
    expect(page.locator("body")).to_have_class(__import__("re").compile(r".*theme-polar.*"))
    expect(page.locator('[data-theme="polar"]')).to_have_attribute("aria-pressed", "true")
    screenshot(page, f"{size_name}_05_polar_preview")

    # Cancel must go back to previous theme (Nebula in fresh session).
    page.get_by_role("button", name="이전 화면으로").click()
    expect(page.locator("body")).to_have_class(__import__("re").compile(r".*theme-nebula.*"))
    expect(page.locator("#dashboard-view")).to_be_visible()

    page.get_by_role("button", name="화면 다시 설계").click()
    page.get_by_role("button", name="Studio 시안 미리보기").click()
    page.get_by_role("button", name="선택한 디자인 적용").click()
    expect(page.locator("body")).to_have_class(__import__("re").compile(r".*theme-studio.*"))
    expect(page.locator("#dashboard-view")).to_be_visible()
    screenshot(page, f"{size_name}_06_studio_applied")

    page.get_by_role("button", name="저장한 기억").click()
    expect(page.locator("#memories-view")).to_be_visible()
    screenshot(page, f"{size_name}_07_memories")
    page.get_by_role("button", name="작업 공간으로").click()

    # Existing input command should keep working after transitions.
    page.locator("#command-input").fill("자비스 대시보드 좀 바꿔")
    page.locator("#command-form button[type=submit]").click()
    expect(page.locator("#variants-view")).to_be_visible()
    page.get_by_role("button", name="이전 화면으로").click()

    # Presence state should remain available.
    page.get_by_role("button", name="닫기").click()
    expect(page.locator("#workspace")).to_be_hidden()


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
