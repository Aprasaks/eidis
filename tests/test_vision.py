import base64
import json
import os
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from jarvis.vision import VisionError, VisionRemoteError, analyze_screen, validate_image, vision_ready
from jarvis.server import make_server


def example_image():
    # This is a small fake JPEG-shaped buffer, not a real screenshot.
    # Tests never upload the user's display or spend API credits.
    raw = b"\xff\xd8\xff" + b"\x00" * 1000 + b"\xff\xd9"
    return "data:image/jpeg;base64," + base64.b64encode(raw).decode()


class VisionTests(unittest.TestCase):
    def test_image_validation(self):
        good = example_image()
        self.assertEqual(validate_image(good), good)
        for invalid in ("", "data:image/png;base64,AA==", "data:image/jpeg;base64,!!",
                        "data:image/jpeg;base64," + base64.b64encode(b"not-a-jpeg" * 80).decode(),
                        "data:image/jpeg;base64," + ("A" * 1400000)):
            with self.subTest(invalid=invalid[:40]), self.assertRaises(VisionError):
                validate_image(invalid)

    def test_default_disconnected_and_explicit_consent(self):
        with patch.dict(os.environ, {"OPENAI_API_KEY": "", "JARVIS_ENABLE_VISION_API": "0"}):
            self.assertFalse(vision_ready())
            with self.assertRaises(VisionError):
                analyze_screen("지금 화면 설명해 줘", example_image(), consent=True)
        with patch.dict(os.environ, {"OPENAI_API_KEY": "fake", "JARVIS_ENABLE_VISION_API": "1"}):
            with self.assertRaises(VisionError):
                analyze_screen("지금 화면 설명해 줘", example_image(), consent=False)

    def test_mock_responses_model_receives_one_image_without_storage_or_tools(self):
        response = json.dumps({
            "output": [{"type": "message", "content": [
                {"type": "output_text", "text": "이 화면은 설정 목록으로 보입니다. 버튼이 하나 보입니다."}
            ]}]
        }).encode()

        class FakeHTTP:
            def __enter__(self): return self
            def __exit__(self, *_): return False
            def read(self, _): return response

        def fake_open(request, timeout):
            self.assertEqual(request.full_url, "https://api.openai.com/v1/responses")
            self.assertEqual(request.get_header("Authorization"), "Bearer test-secret")
            data = json.loads(request.data)
            self.assertFalse(data["store"])
            self.assertNotIn("tools", data)
            self.assertEqual(data["input"][0]["content"][1]["type"], "input_image")
            self.assertEqual(data["input"][0]["content"][1]["image_url"], example_image())
            return FakeHTTP()

        with patch.dict(os.environ, {
            "OPENAI_API_KEY": "test-secret", "JARVIS_ENABLE_VISION_API": "1",
            "JARVIS_VISION_MODEL": "gpt-6.1-terra"
        }), patch("jarvis.vision.urlopen", side_effect=fake_open):
            data = analyze_screen("지금 화면 설명해 줘", example_image(), consent=True)
        self.assertIn("설정 목록", data["text"])
        self.assertEqual(data["source"], "ai_image")
        self.assertIn("실제 앱 조작은 하지", data["scope"])

    def test_broken_provider_response_is_failure_not_fake_analysis(self):
        class FakeHTTP:
            def __enter__(self): return self
            def __exit__(self, *_): return False
            def read(self, _): return b'{"output": []}'
        with patch.dict(os.environ, {"OPENAI_API_KEY": "test", "JARVIS_ENABLE_VISION_API": "1"}), \
             patch("jarvis.vision.urlopen", return_value=FakeHTTP()):
            with self.assertRaises(VisionRemoteError):
                analyze_screen("지금 화면 설명해 줘", example_image(), consent=True)

    def test_http_same_origin_and_paid_attempt_fuse(self):
        with tempfile.TemporaryDirectory() as td:
            httpd = make_server(port=0, db_path=Path(td) / "vision.sqlite3")
            thread = threading.Thread(target=httpd.serve_forever, daemon=True)
            thread.start()
            address = f"http://127.0.0.1:{httpd.server_port}"
            payload = {"question": "현재 화면에 무엇이 보여?", "image": example_image(), "consent": True}
            seen = []

            def post(data, origin=None):
                request = Request(
                    address + "/api/vision/analyze",
                    data=json.dumps(data, ensure_ascii=False).encode(),
                    method="POST",
                    headers={"Content-Type": "application/json", "Origin": origin or address}
                )
                return urlopen(request)

            def fake_analyze(q, image, *, consent):
                self.assertEqual(q, payload["question"])
                self.assertTrue(consent)
                seen.append(image)
                return {"text": "모의 화면 분석 성공", "source": "ai_image", "scope": "한 장"}

            try:
                with patch.dict(os.environ, {"OPENAI_API_KEY": "", "JARVIS_ENABLE_VISION_API": "0"}):
                    with urlopen(address + "/api/status") as response:
                        status = json.load(response)
                    self.assertFalse(status["vision"]["remote_configured"])
                    with self.assertRaises(HTTPError) as exc:
                        post(payload)
                    self.assertEqual(exc.exception.code, 400)
                    self.assertEqual(httpd.vision_calls, 0)

                with patch.dict(os.environ, {"OPENAI_API_KEY": "test", "JARVIS_ENABLE_VISION_API": "1"}), \
                     patch("jarvis.server.analyze_screen", side_effect=fake_analyze):
                    with self.assertRaises(HTTPError) as exc:
                        post({**payload, "consent": False})
                    self.assertEqual(exc.exception.code, 400)
                    with self.assertRaises(HTTPError) as exc:
                        post(payload, origin="https://malicious.example")
                    self.assertEqual(exc.exception.code, 403)
                    with self.assertRaises(HTTPError) as exc:
                        post({**payload, "image": "data:image/jpeg;base64,invalid"})
                    self.assertEqual(exc.exception.code, 400)
                    self.assertEqual(httpd.vision_calls, 0)

                    for _ in range(3):
                        with post(payload) as response:
                            self.assertEqual(json.load(response)["text"], "모의 화면 분석 성공")
                    self.assertEqual(httpd.vision_calls, 3)
                    self.assertEqual(len(seen), 3)
                    with self.assertRaises(HTTPError) as exc:
                        post(payload)
                    self.assertEqual(exc.exception.code, 400)

                with urlopen(address + "/api/activity") as response:
                    activity = json.load(response)
                self.assertEqual(activity["items"], [])
                self.assertNotIn("data:image", json.dumps(activity))
            finally:
                httpd.shutdown();httpd.server_close()
                httpd.RequestHandlerClass.store.close();thread.join(timeout=3)


if __name__ == "__main__":
    unittest.main()
