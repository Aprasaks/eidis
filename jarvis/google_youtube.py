"""Local-only, read-only Google YouTube OAuth with PKCE and macOS Keychain.

Never serialize access/refresh tokens, OAuth codes or secrets to JARVIS logs,
SQLite, the UI, or the repository. Only the account owner grants consent.
"""
from __future__ import annotations

import base64
import ctypes
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import secrets
import threading
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

CONFIG = Path.home() / ".jarvis-lab" / "oauth" / "youtube-client.json"
KEYCHAIN_SERVICE = b"dev.dechive.jarvis.google.youtube"
KEYCHAIN_ACCOUNT = b"primary"
SCOPES = (
    "https://www.googleapis.com/auth/youtube.readonly",
    "https://www.googleapis.com/auth/yt-analytics.readonly",
)
AUTH_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
YT_DATA = "https://youtube.googleapis.com/youtube/v3/channels"
YT_ANALYTICS = "https://youtubeanalytics.googleapis.com/v2/reports"


class YouTubeConnectionError(Exception):
    pass


def _keychain():
    if os.uname().sysname != "Darwin":
        raise YouTubeConnectionError("macOS Keychain에서만 토큰을 보관합니다.")
    lib = ctypes.CDLL("/System/Library/Frameworks/Security.framework/Security")
    lib.SecKeychainFindGenericPassword.argtypes = [
        ctypes.c_void_p, ctypes.c_uint32, ctypes.c_char_p, ctypes.c_uint32,
        ctypes.c_char_p, ctypes.POINTER(ctypes.c_uint32),
        ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(ctypes.c_void_p)]
    lib.SecKeychainFindGenericPassword.restype = ctypes.c_int32
    lib.SecKeychainAddGenericPassword.argtypes = [
        ctypes.c_void_p, ctypes.c_uint32, ctypes.c_char_p, ctypes.c_uint32,
        ctypes.c_char_p, ctypes.c_uint32, ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_void_p)]
    lib.SecKeychainAddGenericPassword.restype = ctypes.c_int32
    lib.SecKeychainItemModifyAttributesAndData.argtypes = [
        ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p]
    lib.SecKeychainItemModifyAttributesAndData.restype = ctypes.c_int32
    lib.SecKeychainItemFreeContent.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    lib.SecKeychainItemFreeContent.restype = ctypes.c_int32
    return lib


def _find_token() -> str | None:
    lib = _keychain()
    length = ctypes.c_uint32()
    data = ctypes.c_void_p()
    status = lib.SecKeychainFindGenericPassword(
        None, len(KEYCHAIN_SERVICE), KEYCHAIN_SERVICE,
        len(KEYCHAIN_ACCOUNT), KEYCHAIN_ACCOUNT,
        ctypes.byref(length), ctypes.byref(data), None)
    if status == -25300:
        return None
    if status != 0:
        raise YouTubeConnectionError("Mac Keychain 토큰 읽기 권한을 확인해 주세요.")
    try:
        return ctypes.string_at(data, length.value).decode("utf-8")
    finally:
        lib.SecKeychainItemFreeContent(None, data)


def _store_token(token: str):
    lib = _keychain()
    payload = token.encode("utf-8")
    buffer = ctypes.create_string_buffer(payload)
    item = ctypes.c_void_p()
    status = lib.SecKeychainFindGenericPassword(
        None, len(KEYCHAIN_SERVICE), KEYCHAIN_SERVICE,
        len(KEYCHAIN_ACCOUNT), KEYCHAIN_ACCOUNT,
        None, None, ctypes.byref(item))
    if status == -25300:
        status = lib.SecKeychainAddGenericPassword(
            None, len(KEYCHAIN_SERVICE), KEYCHAIN_SERVICE,
            len(KEYCHAIN_ACCOUNT), KEYCHAIN_ACCOUNT,
            len(payload), buffer, None)
    elif status == 0:
        status = lib.SecKeychainItemModifyAttributesAndData(
            item, None, len(payload), buffer)
    if status != 0:
        raise YouTubeConnectionError("Mac Keychain에 인증 정보를 저장하지 못했습니다.")


def _client():
    try:
        stat = CONFIG.stat()
        if stat.st_mode & 0o077:
            raise YouTubeConnectionError("Google 클라이언트 파일 권한을 600으로 제한해 주세요.")
        obj = json.loads(CONFIG.read_text(encoding="utf-8"))["installed"]
        if obj.get("project_id") != "dechive-jarvis":
            raise YouTubeConnectionError("DECHIVE-JARVIS Google 프로젝트 파일이 아닙니다.")
        if not obj.get("client_id") or not obj.get("client_secret"):
            raise YouTubeConnectionError("Google OAuth 클라이언트 설정이 불완전합니다.")
        return obj
    except (FileNotFoundError, KeyError, ValueError) as exc:
        raise YouTubeConnectionError("JARVIS Google OAuth 클라이언트 파일이 없습니다.") from exc


def _request_json(url: str, *, post: dict | None = None, token: str | None = None):
    if post is None:
        request = Request(url, headers={"Accept": "application/json"})
    else:
        encoded = urlencode(post).encode("utf-8")
        request = Request(url, data=encoded, headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json"})
    if token is not None:
        request.add_header("Authorization", "Bearer " + token)
    try:
        with urlopen(request, timeout=12) as response:
            if response.status != 200:
                raise YouTubeConnectionError("Google API가 요청을 거절했습니다.")
            raw = response.read(700_000)
        return json.loads(raw)
    except (HTTPError, URLError, TimeoutError, json.JSONDecodeError) as exc:
        # Never include exception/response body, which may contain private data.
        code = getattr(exc, "code", None)
        label = str(code) if isinstance(code, int) else "network"
        raise YouTubeConnectionError("Google API 연결 실패 (" + label + ").") from None


class GoogleYouTubeConnection:
    def __init__(self):
        self.lock = threading.Lock()
        self.pending: dict | None = None
        self.cache: dict | None = None
        self.cache_at = 0.0
        self.access_token: str | None = None
        self.access_expires_at = 0.0

    def status(self):
        try:
            _client()
            connected = _find_token() is not None
            return {"configured": True, "connected": connected,
                    "status": "connected" if connected else "awaiting_google_consent",
                    "scopes": list(SCOPES)}
        except YouTubeConnectionError as exc:
            return {"configured": CONFIG.exists(), "connected": False,
                    "status": "needs_setup", "message": str(exc)}

    def begin(self, port: int):
        client = _client()
        verifier = secrets.token_urlsafe(64)
        challenge = base64.urlsafe_b64encode(
            hashlib.sha256(verifier.encode("ascii")).digest()
        ).rstrip(b"=").decode("ascii")
        state = secrets.token_urlsafe(32)
        redirect = "http://127.0.0.1:" + str(port) + "/api/youtube/oauth/callback"
        with self.lock:
            self.pending = {"state": state, "verifier": verifier,
                            "redirect": redirect, "expires": time.monotonic() + 300}
        params = {
            "client_id": client["client_id"],
            "redirect_uri": redirect, "response_type": "code",
            "scope": " ".join(SCOPES), "state": state,
            "access_type": "offline", "prompt": "consent",
            "code_challenge": challenge, "code_challenge_method": "S256",
        }
        return {"authorization_url": AUTH_ENDPOINT + "?" + urlencode(params)}

    def finish(self, query: dict):
        code = (query.get("code") or [""])[0]
        state = (query.get("state") or [""])[0]
        with self.lock:
            pending = self.pending
            self.pending = None
        if not pending or time.monotonic() > pending["expires"] or not secrets.compare_digest(
            state, pending["state"]
        ):
            raise YouTubeConnectionError("OAuth 인증 세션이 유효하지 않습니다. 다시 연결해 주세요.")
        if not code:
            raise YouTubeConnectionError("Google 계정에서 인증을 승인하지 않았습니다.")
        client = _client()
        reply = _request_json(TOKEN_ENDPOINT, post={
            "client_id": client["client_id"],
            "client_secret": client["client_secret"],
            "code": code, "redirect_uri": pending["redirect"],
            "grant_type": "authorization_code",
            "code_verifier": pending["verifier"],
        })
        token = reply.get("refresh_token")
        granted = set(reply.get("scope", "").split())
        if not token or not set(SCOPES).issubset(granted):
            raise YouTubeConnectionError("Google의 필요한 읽기 권한이나 재인증 토큰을 받지 못했습니다.")
        _store_token(token)
        with self.lock:
            self.access_token = reply.get("access_token")
            self.access_expires_at = time.monotonic() + min(3500, int(reply.get("expires_in", 3600)) - 60)
            self.cache = None
        return {"connected": True}

    def _access(self):
        with self.lock:
            if self.access_token and time.monotonic() < self.access_expires_at:
                return self.access_token
        refresh_token = _find_token()
        if refresh_token is None:
            raise YouTubeConnectionError("먼저 Google 계정을 연결해 주세요.")
        client = _client()
        reply = _request_json(TOKEN_ENDPOINT, post={
            "client_id": client["client_id"],
            "client_secret": client["client_secret"],
            "refresh_token": refresh_token,
            "grant_type": "refresh_token",
        })
        access_token = reply.get("access_token")
        if not access_token:
            raise YouTubeConnectionError("Google 인증이 만료되었습니다. 재연결해 주세요.")
        with self.lock:
            self.access_token = access_token
            self.access_expires_at = time.monotonic() + max(30, int(reply.get("expires_in", 3600)) - 60)
        return access_token

    def summary(self):
        with self.lock:
            if self.cache is not None and time.monotonic() - self.cache_at < 300:
                return self.cache
        access = self._access()
        info = _request_json(YT_DATA + "?" + urlencode({
            "part": "snippet,statistics", "mine": "true"}), token=access)
        channels = info.get("items", [])
        if not channels:
            raise YouTubeConnectionError("연결된 Google 계정에서 YouTube 채널을 찾지 못했습니다.")
        channel = channels[0]
        now = datetime.now(timezone.utc).date()
        start = now - timedelta(days=29)
        end = now - timedelta(days=2)
        basic = {
            "channel_id": channel.get("id", ""),
            "channel_title": channel.get("snippet", {}).get("title", ""),
            "thumbnail_url": next((item.get("url") for quality in ("high", "medium", "default")
                                   if isinstance((item := channel.get("snippet", {}).get("thumbnails", {}).get(quality)), dict)
                                   and isinstance(item.get("url"), str) and item.get("url", "").startswith("https://")), None),
            "subscriber_count": channel.get("statistics", {}).get("subscriberCount"),
            "video_count": channel.get("statistics", {}).get("videoCount"),
            "channel_views": channel.get("statistics", {}).get("viewCount"),
            "period_start": start.isoformat(), "period_end": end.isoformat(),
            "analytics": None, "analytics_error": None,
            "checked_at": datetime.now(timezone.utc).isoformat(),
        }
        try:
            report = _request_json(YT_ANALYTICS + "?" + urlencode({
                "ids": "channel==MINE", "startDate": start.isoformat(),
                "endDate": end.isoformat(),
                "metrics": "views,estimatedMinutesWatched,subscribersGained",
            }), token=access)
            rows = report.get("rows", [])
            if rows and len(rows[0]) >= 3:
                basic["analytics"] = {
                    "views": int(rows[0][0]),
                    "estimated_minutes_watched": float(rows[0][1]),
                    "subscribers_gained": int(rows[0][2]),
                }
            else:
                basic["analytics_error"] = "이 기간에 분석 데이터가 없습니다."
        except YouTubeConnectionError:
            basic["analytics_error"] = "YouTube Analytics 데이터를 가져오지 못했습니다."
        with self.lock:
            self.cache = basic
            self.cache_at = time.monotonic()
        return basic
