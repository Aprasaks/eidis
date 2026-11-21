"""Real-clock answers and staged local Qwen performance protections."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
CLOCK=(ROOT/"macos/Sources/EidisMac/JarvisLocalClockAndRouting.swift").read_text()
STREAM=(ROOT/"macos/Sources/EidisMac/JarvisOllamaTextStream.swift").read_text()
WARM=(ROOT/"macos/Sources/EidisMac/JarvisLocalModelWarmup.swift").read_text()
CHAT=(ROOT/"macos/Sources/EidisMac/JarvisOverlayConversation.swift").read_text()
APP=(ROOT/"macos/Sources/EidisMac/JarvisBundledServer.swift").read_text()
VIEW=(ROOT/"macos/Sources/EidisMac/JarvisFullscreenOverlay.swift").read_text()
PANEL=(ROOT/"macos/Sources/EidisMac/JarvisLiveDialoguePanel.swift").read_text()
CI=(ROOT/".github/workflows/ci.yml").read_text()

class LiveClockAndSpeedTests(unittest.TestCase):
    def test_date_queries_never_require_the_llm(self):
        a=CHAT.index("if let clock = JarvisLocalClock.parse(prompt)")
        b=CHAT.index("if let intent = JarvisBrowserControlIntent.parse(prompt)")
        c=CHAT.index('let url = URL(string: "http://127.0.0.1:11434/api/chat")!')
        self.assertLess(a,b)
        self.assertLess(b,c)
        self.assertIn("return JarvisLocalClock.answer(clock)",CHAT)
        self.assertIn("DateFormatter()",CLOCK)
        self.assertIn("now: Date = Date()",CLOCK)
        self.assertIn("zone: TimeZone = .current",CLOCK)
        self.assertNotIn("2026년 5월",CLOCK)
        self.assertIn("JarvisLocalClock.context()",CHAT)
        self.assertIn("macos/tests/clock-speed/main.swift",CI)

    def test_regular_chat_streams_without_tools_and_actions_keep_registry(self):
        self.assertIn("let useFastStream = JarvisConversationSpeedRoute.shouldStreamWithoutTools(prompt)",CHAT)
        self.assertIn('body.removeValue(forKey: "tools")',CHAT)
        self.assertIn('body["stream"] = true',CHAT)
        self.assertIn('"tools": JarvisCommand.tools',CHAT)
        self.assertIn('"stream": false',CHAT)
        self.assertIn("JarvisOllamaTextStream.receive(",CHAT)
        self.assertIn("session.bytes(for:request)",STREAM)
        self.assertIn("try Task.checkCancellation()",STREAM)
        self.assertIn("guard finished else",STREAM)
        self.assertIn("chunk.message?.toolCalls?.isEmpty != false",STREAM)
        self.assertIn("Date().timeIntervalSince(started)*1000",STREAM)
        self.assertIn("streamingAnswer = \"\"",CHAT)
        self.assertIn("self.streamingAnswer = partial",CHAT)
        self.assertIn("token == self.generation",CHAT)

    def test_streaming_draft_is_visible_and_not_persisted(self):
        self.assertIn("dialogue.streamingAnswer",VIEW)
        self.assertIn("dialogue.streamingAnswer",PANEL)
        self.assertIn("답변 작성 중 · 최종 답변 아님",PANEL)
        self.assertIn("작성 중 · 아직 최종 답변 아님",VIEW)
        self.assertLess(CHAT.index("streamingAnswer = \"\"",CHAT.index("private func handleQuestion")),
                        CHAT.index("dialogueTurns.append(JarvisLiveDialogueTurn(role: \"DECHIVE\"",CHAT.index("private func handleQuestion")))
        self.assertIn("conversation.append([\"role\": \"assistant\", \"content\": output])",CHAT)

    def test_preload_is_local_no_generated_text_and_can_fail_harmlessly(self):
        self.assertIn("JarvisLocalModelWarmup()",APP)
        self.assertIn("localModelWarmup.start()",APP)
        self.assertIn("localModelWarmup.stop()",APP)
        self.assertIn("http://127.0.0.1:11434/api/generate",WARM)
        self.assertIn('"keep_alive":"2m"',WARM)
        self.assertIn('"stream":false',WARM)
        self.assertIn('object["model"] as? String',WARM)
        self.assertNotIn('"prompt"',WARM)
        self.assertNotIn("api.openai.com",WARM)
        self.assertNotIn("api.anthropic.com",WARM)
        self.assertIn('NSLog("DECHIVE local Ollama preload unavailable")',WARM)

if __name__=="__main__":
    unittest.main()
