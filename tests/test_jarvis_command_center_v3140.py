import unittest
from pathlib import Path
R=Path(__file__).resolve().parents[1]
COMMAND=(R/'macos/Sources/EidisMac/JarvisCommandCenterView.swift').read_text()
OVERLAY=(R/'macos/Sources/EidisMac/JarvisFullscreenOverlay.swift').read_text()
GIT=(R/'macos/Sources/EidisMac/JarvisLocalGitScanner.swift').read_text()
LIVE=(R/'macos/Sources/EidisMac/JarvisLiveDashboard.swift').read_text()
INFO=(R/'macos/Resources/Info.plist').read_text()
class CommandCenterContract(unittest.TestCase):
    def test_original_core_only_changes_position_not_video_asset(self):
        for text in ('JarvisLoopingCore(videoURL: videoURL, compact: commandCenter)',
                     'AVPlayerLooper(player: player', 'videoGravity = compact ? .resizeAspectFill : .resizeAspect',
                     '.animation(reduceMotion ? nil : .easeInOut(duration: 0.72)',
                     'JarvisCommandCenterView(model: liveDashboard)',
                     'liveDashboard.mode == .overview', 'area.size.height * (wide ? 0.235 : 0.18)',
                     'dialogue?.cancel()', 'hotkey?.uninstallEscape()'):
            self.assertIn(text,OVERLAY)
        self.assertNotIn('JARVIS_Activation_Alpha_HEVC.mov',OVERLAY)
    def test_read_only_live_sources_not_fake_simulation(self):
        for text in ('/api/activity','/api/projects','/api/vault?limit=12',
                     'JarvisLocalGitScanner.scan()', 'sourceChecks.insert(',
                     'while !Task.isCancelled', 'pollingTask?.cancel()',
                     'worker.cancel()', 'recordCheck("로컬 Git"',
                     '"관제실보여"'):
            self.assertIn(text,LIVE)
        for text in ('GIT_OPTIONAL_LOCKS','GIT_TERMINAL_PROMPT',
                     '--untracked-files=no','maximumRepositories = 35',
                     'maximumDirectories = 1200', 'maximumDepth = 3',
                     'process.executableURL = URL(fileURLWithPath: "/usr/bin/git")'):
            self.assertIn(text,GIT)
        for forbidden in ('git push','git fetch','git checkout','INSERT INTO','api.github.com'):
            self.assertNotIn(forbidden,GIT)
    def test_tv_readable_layout_and_provenance(self):
        for text in ('width < 1120', 'min(2.0, max(0.84', 'ScrollView(.vertical)',
                     'PROJECT OPERATIONS','GIT WORKTREES','YOUTUBE / 채널 분석',
                     'API NOT CONNECTED','LOCAL GIT', 'LIVE CHECKS',
                     'RECORDED EVENTS', 'model.sourceChecks',
                     'model.recordedActivity', 'model.gitSnapshot',
                     '실제 기록 시각', 'GitHub 원격 저장소 전체 현황은 아직 연결되지 않았습니다.'):
            self.assertIn(text,COMMAND)
        self.assertNotIn('fake statistics', COMMAND.lower())
        self.assertIn('<string>3.14.3</string>', INFO)
if __name__=='__main__':unittest.main()
