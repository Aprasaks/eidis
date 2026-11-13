import json
import os
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from jarvis.design import (
    DesignError, RemoteDesignError, _validated_proposals, contrast,
    local_suggestions, remote_ready, suggest_designs,
)
from jarvis.server import make_server


class DesignTests(unittest.TestCase):
    def test_local_prompts_really_change_palette_and_density(self):
        dark = suggest_designs("대시보드 더 어둡고 간결하게 바꿔", provider="rules")
        green = suggest_designs("따뜻한 민트 녹색으로 조금 더 정보를 보여줘", provider="rules")
        self.assertEqual(dark["provider"], "rules")
        self.assertEqual(len(dark["proposals"]), 4)
        self.assertNotEqual(dark["proposals"][0]["accent"], green["proposals"][0]["accent"])
        self.assertEqual(dark["proposals"][0]["density"], "airy")
        self.assertEqual(dark["proposals"], suggest_designs("대시보드 더 어둡고 간결하게 바꿔")["proposals"])

    def test_safe_values_and_contrast(self):
        values = local_suggestions("파란색 우주처럼 바꿔")
        for spec in values:
            self.assertGreaterEqual(contrast(spec["background"], spec["foreground"]), 7)
            self.assertGreaterEqual(contrast(spec["background"], spec["accent"]), 3)
            self.assertIn(spec["layout"], ("balanced", "focus", "panorama"))
            self.assertIn(spec["orb"], ("thin", "soft", "radiant"))
            self.assertEqual(spec["source"], "rules")

    def test_rejects_commands_in_design_fields(self):
        valid = local_suggestions("더 검고 간결하게")
        malformed = [{k: v for k, v in spec.items() if k not in ("id", "source")} for spec in valid]
        malformed[0]["background"] = "url(javascript:alert(1))"
        with self.assertRaises(DesignError):
            _validated_proposals(malformed, "ai")
        malformed[0]["background"] = "#ffffff"
        with self.assertRaises(DesignError):
            _validated_proposals(malformed, "ai")

    def test_never_calls_remote_without_config_and_explicit_consent(self):
        with patch.dict(os.environ, {"OPENAI_API_KEY": "", "JARVIS_ENABLE_DESIGN_API": "0"}):
            self.assertFalse(remote_ready())
            with self.assertRaises(DesignError):
                suggest_designs("더 간결한 디자인으로 만들어", provider="ai", consent=False)
            with self.assertRaises(DesignError):
                suggest_designs("더 간결한 디자인으로 만들어", provider="ai", consent=True)

    def test_remote_provider_adapter_with_fake_response(self):
        template = [{k: v for k, v in item.items() if k not in ("id", "source")}
                    for item in local_suggestions("짙은 밤색으로 바꿔")]
        fake_response = json.dumps({
            "output": [{"type": "message", "content": [
                {"type": "output_text", "text": json.dumps({"proposals": template})}
            ]}]
        }).encode("utf-8")

        class FakeHTTP:
            def __enter__(self):
                return self
            def __exit__(self, *args):
                return False
            def read(self, limit):
                return fake_response

        def fake_urlopen(req, timeout):
            self.assertEqual(req.full_url, "https://api.openai.com/v1/responses")
            payload = json.loads(req.data)
            self.assertFalse(payload["store"])
            self.assertEqual(payload["text"]["format"]["type"], "json_schema")
            self.assertEqual(len(payload["input"]), 1)
            self.assertEqual(req.get_header("Authorization"), "Bearer mock-not-real")
            return FakeHTTP()

        with patch.dict(os.environ, {
            "OPENAI_API_KEY": "mock-not-real", "JARVIS_ENABLE_DESIGN_API": "1",
            "JARVIS_DESIGN_MODEL": "gpt-6-luna"
        }):
            with patch("jarvis.design.urlopen", side_effect=fake_urlopen):
                result = suggest_designs("더 간결한 디자인을 제안해줘", provider="ai", consent=True)
        self.assertEqual(result["provider"], "ai")
        self.assertEqual(len(result["proposals"]), 4)
        self.assertTrue(all(item["source"] == "ai" for item in result["proposals"]))

    def test_bad_provider_and_text(self):
        for phrase in ("", "a" * 321):
            with self.assertRaises(DesignError):
                local_suggestions(phrase)
        with self.assertRaises(DesignError):
            suggest_designs("좀 더 어두운 화면", provider="unknown")

    def test_http_endpoint_local_only(self):
        with tempfile.TemporaryDirectory() as td:
            httpd = make_server(port=0, db_path=Path(td) / "design.sqlite3")
            thread = threading.Thread(target=httpd.serve_forever, daemon=True)
            thread.start()
            base = f"http://127.0.0.1:{httpd.server_port}"
            try:
                def post(payload, *, origin=None):
                    req = Request(
                        base + "/api/design/suggest",
                        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
                        method="POST",
                        headers={"Content-Type": "application/json", "Origin": origin or base}
                    )
                    return urlopen(req)
                with post({"prompt": "대시보드 더 어둡게", "provider": "rules"}) as r:
                    data = json.load(r)
                self.assertEqual(len(data["proposals"]), 4)
                self.assertEqual(data["origin"], "로컬 규칙 기반")
                with urlopen(base + "/api/activity") as r:
                    activity = json.load(r)
                self.assertEqual(activity["items"][0]["category"], "design_suggestions")
                self.assertNotIn("더 어둡게", json.dumps(activity, ensure_ascii=False))
                with self.assertRaises(HTTPError) as e:
                    post({"prompt": "좀 더 어둡게", "provider": "ai", "consent": False})
                self.assertEqual(e.exception.code, 400)
                with self.assertRaises(HTTPError) as e:
                    post({"prompt": "더 어둡게", "provider": "rules"},
                         origin="https://attacker.example")
                self.assertEqual(e.exception.code, 403)
            finally:
                httpd.shutdown()
                httpd.server_close()
                httpd.RequestHandlerClass.store.close()
                thread.join(timeout=3)


if __name__ == "__main__":
    unittest.main()
