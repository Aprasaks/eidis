"""JARVIS local voice server (Kokoro-82M via mlx-audio). Free, offline after the first model download.

- Listens on 127.0.0.1 only. No auth because nothing outside this Mac can reach it.
- POST /tts  {"text": "...", "voice": "af_heart", "speed": 1.0}  ->  audio/wav (24 kHz, 16-bit mono)
- GET  /health -> {"ok": true, "voice": "af_heart"}
- The model stays loaded so each sentence takes well under a second.

Run with the isolated venv:  ~/.jarvis-lab/tts/venv/bin/python -I jarvis_tts_server.py
"""
import io
import json
import re
import sys
import threading
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
from mlx_audio.tts.utils import load_model

HOST, PORT = "127.0.0.1", 8792
MODEL_ID = "mlx-community/Kokoro-82M-bf16"
DEFAULT_VOICE = "af_heart"
VOICES = re.compile(r"^(a|b)(f|m)_[a-z]{2,12}$")
MAX_CHARS = 1200

model = load_model(MODEL_ID)
lock = threading.Lock()  # one synthesis at a time (shared model)


def loudness(audio):
    """Kokoro output is quiet (peak about -9 dBFS, mean about -27 dB).
    Raise speech to roughly -16 dB RMS, then soft-limit so peaks never clip."""
    peak = float(np.max(np.abs(audio))) if audio.size else 0.0
    rms = float(np.sqrt(np.mean(audio ** 2))) if audio.size else 0.0
    if peak < 1e-4 or rms < 1e-5:
        return audio
    target_rms = 10 ** (-16 / 20)
    gain = min(target_rms / rms, 8.0)
    boosted = audio * gain
    return (np.tanh(boosted * 1.1) / np.tanh(1.1)).astype(np.float32) * 0.97


def synthesize(text: str, voice: str, speed: float) -> bytes:
    chunks = []
    with lock:
        for result in model.generate(text=text, voice=voice, speed=speed, lang_code=voice[0]):
            chunks.append(np.asarray(result.audio, dtype=np.float32))
    audio = np.concatenate(chunks) if chunks else np.zeros(1, dtype=np.float32)
    audio = loudness(audio)
    pcm = (np.clip(audio, -1, 1) * 32767).astype("<i2").tobytes()
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(24000)
        wav.writeframes(pcm)
    return buffer.getvalue()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # no request logging (text may be private)
        pass

    def _send(self, status, body, ctype="application/json"):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, json.dumps({"ok": True, "voice": DEFAULT_VOICE}).encode())
        else:
            self._send(404, b"{}")

    def do_POST(self):
        if self.path != "/tts":
            return self._send(404, b"{}")
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 16_000:
                return self._send(413, b"{}")
            req = json.loads(self.rfile.read(length))
            text = str(req.get("text", "")).strip()[:MAX_CHARS]
            voice = str(req.get("voice", DEFAULT_VOICE))
            speed = float(req.get("speed", 1.0))
            if not text or not VOICES.match(voice) or not (0.6 <= speed <= 1.5):
                return self._send(400, b"{}")
            self._send(200, synthesize(text, voice, speed), "audio/wav")
        except Exception:
            self._send(500, b"{}")


if __name__ == "__main__":
    synthesize("Ready.", DEFAULT_VOICE, 1.0)  # warm up
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"JARVIS voice ready on http://{HOST}:{PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)
