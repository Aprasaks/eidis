from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
DASH = (ROOT/'macos/Sources/EidisMac/JarvisOverlayDashboard.swift').read_text()
CHAT = (ROOT/'macos/Sources/EidisMac/JarvisOverlayConversation.swift').read_text()
OVERLAY = (ROOT/'macos/Sources/EidisMac/JarvisFullscreenOverlay.swift').read_text()
VOICE = (ROOT/'macos/Sources/EidisMac/ElevenLabsVoiceService.swift').read_text()
VOICE_UI = (ROOT/'macos/Sources/EidisMac/NativeSpeech.swift').read_text()

class OnDemandDashboard(unittest.TestCase):
    def test_explicit_read_only_command_and_local_real_data(self):
        for marker in ('enum JarvisDashboardIntent', 'case show, hide',
                       'normalized.contains("대시보드")', 'normalized.contains("작업")',
                       'normalized.contains("프로젝트")', '"보여"', '"띄워"',
                       '"숨겨"', 'http://127.0.0.1:8765/api/projects',
                       'request.httpMethod = "GET"', '.reloadIgnoringLocalCacheData',
                       'decoder.keyDecodingStrategy = .convertFromSnakeCase',
                       'decoder.decode(WorkProjectsReply.self', 'projects = result.items',
                       'projects = [] // never display outdated numbers as fresh',
                       'revision = UUID()', 'session.invalidateAndCancel()'):
            self.assertIn(marker, DASH)
        self.assertNotIn('request.httpMethod = "POST"', DASH)
        self.assertNotIn('https://', DASH)
        self.assertNotIn('project_task_added', DASH)
    def test_dashboard_triggered_instead_of_qwen_only_when_explicit(self):
        for marker in ('let dashboard = JarvisOverlayDashboard()',
                       'case .showDashboard:',
                       'result = await dashboard.show()',
                       'case .dashboard: result = dashboard.hide()',
                       'JarvisCommand.actions(from: message, utterance: prompt)',
                       'dashboard.cancel()'):
            self.assertIn(marker, CHAT)
        for marker in ('if dashboard.isVisible', 'PROJECT STATUS',
                       'ForEach(dashboard.projects)', 'project.nextTasks.prefix(4)',
                       'dashboard.totalTodo', 'dashboard.totalDoing',
                       'dashboard.totalBlocked', 'dashboard.totalDone',
                       'dashboard: dialogue.dashboard',
                       'jarvis-on-demand-dashboard', 'jarvis-dashboard-close'):
            self.assertIn(marker, OVERLAY)
        self.assertIn('DECHIVE_FullHD_Loop', OVERLAY)
        self.assertIn('hotkey?.uninstallEscape()', OVERLAY)
        self.assertIn('if (!dialogue.answer.isEmpty || !dialogue.streamingAnswer.isEmpty)', OVERLAY)
        self.assertIn('subtitles sit on the left', OVERLAY)
        self.assertIn('.padding(.bottom, 89)', OVERLAY)
    def test_voice_request_cap_removed_without_removing_safety(self):
        self.assertNotIn('private static let maxRequests = 5', VOICE)
        self.assertNotIn('guard remaining > 0', VOICE)
        self.assertNotIn('remaining == 0', VOICE_UI)
        self.assertNotIn('/5회', VOICE)
        self.assertNotIn('/5회', VOICE_UI)
        self.assertIn('attempts += 1', VOICE)
        self.assertIn('guard !isBusy else', VOICE)
        self.assertIn('guard phrase.count <= Self.maxCharacters', VOICE)
        self.assertIn('guard (enabled || explicitlyPreviewed) && keyPresent', VOICE)
        self.assertIn('case 402, 429: throw ElevenLabsVoiceError.limitOrCredits', VOICE)
        self.assertIn('guard !Task.isCancelled, generation == speechGeneration', VOICE)

if __name__ == '__main__': unittest.main()
