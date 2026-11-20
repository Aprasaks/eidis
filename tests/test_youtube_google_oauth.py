"""Contract tests for local-only YouTube authorization and failure boundaries."""
import tempfile
from pathlib import Path
import json
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

from jarvis import google_youtube as yt


class GoogleYouTubeContract(unittest.TestCase):
    def test_readonly_scopes_only(self):
        self.assertEqual(yt.SCOPES, (
            "https://www.googleapis.com/auth/youtube.readonly",
            "https://www.googleapis.com/auth/yt-analytics.readonly",
        ))

    def test_pkce_state_and_local_loopback(self):
        connector = yt.GoogleYouTubeConnection()
        fake = {"client_id": "test-client", "client_secret": "not-a-real-secret"}
        with patch.object(yt, "_client", return_value=fake):
            result = connector.begin(8765)
        uri = urlsplit(result["authorization_url"])
        self.assertEqual(uri.scheme, "https")
        self.assertEqual(uri.netloc, "accounts.google.com")
        args = parse_qs(uri.query)
        self.assertEqual(args["code_challenge_method"], ["S256"])
        self.assertEqual(args["access_type"], ["offline"])
        self.assertEqual(args["response_type"], ["code"])
        self.assertEqual(args["redirect_uri"],
                         ["http://127.0.0.1:8765/api/youtube/oauth/callback"])
        self.assertNotIn("client_secret", args)
        self.assertTrue(len(args["state"][0]) > 20)

    def test_invalid_state_never_calls_token_endpoint(self):
        connector = yt.GoogleYouTubeConnection()
        fake = {"client_id": "test-client", "client_secret": "not-a-real-secret"}
        with patch.object(yt, "_client", return_value=fake):
            connector.begin(8765)
        with patch.object(yt, "_request_json") as remote:
            with self.assertRaises(yt.YouTubeConnectionError):
                connector.finish({"code": ["fake-code"], "state": ["wrong"]})
            remote.assert_not_called()

    def test_unconfigured_credentials_have_safe_status(self):
        with tempfile.TemporaryDirectory() as d, patch.object(
            yt, "CONFIG", Path(d) / "no-config.json"
        ):
            status = yt.GoogleYouTubeConnection().status()
            self.assertFalse(status["connected"])
            self.assertEqual(status["status"], "needs_setup")

    def test_client_file_requires_private_permissions(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "client.json"
            path.write_text(json.dumps({"installed": {
                "project_id": "dechive-jarvis",
                "client_id": "test", "client_secret": "test"}}))
            path.chmod(0o644)
            with patch.object(yt, "CONFIG", path):
                with self.assertRaises(yt.YouTubeConnectionError):
                    yt._client()
            path.chmod(0o600)
            with patch.object(yt, "CONFIG", path):
                self.assertEqual(yt._client()["project_id"], "dechive-jarvis")

    def test_native_ui_decodes_google_authorization_url(self):
        root = Path(__file__).resolve().parents[1]
        ui = (root / "macos/Sources/EidisMac/JarvisLiveDashboard.swift").read_text()
        self.assertIn("decoder.keyDecodingStrategy = .convertFromSnakeCase", ui)
        self.assertIn('decoder.decode(LiveYouTubeAuthReply.self, from: data)', ui)
        self.assertIn('browserURL.host == "accounts.google.com"', ui)
        self.assertIn('importYouTubeClient()', ui)

    def test_cached_summary_avoids_external_calls(self):
        connector = yt.GoogleYouTubeConnection()
        connector.cache = {"channel_title": "test"}
        connector.cache_at = yt.time.monotonic()
        with patch.object(connector, "_access") as remote:
            self.assertEqual(connector.summary()["channel_title"], "test")
            remote.assert_not_called()


if __name__ == "__main__":
    unittest.main()
