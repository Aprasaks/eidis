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
        for text in ('JarvisLoopingCore(videoURL: videoURL, compact: compactCore,',
                     'AVPlayerLooper(player: player', 'videoGravity = compact ? .resizeAspectFill : .resizeAspect',
                     '.animation(reduceMotion ? nil : .easeInOut(duration: 0.72)',
                     'JarvisCommandCenterView(model: liveDashboard, dialogue: dialogue, agentBay: dialogue.agentBay)',
                     'liveDashboard.mode == .overview', 'overviewFrame.midY',
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
    def test_read_only_github_account_scan_and_cache(self):
        github = (R/'macos/Sources/EidisMac/JarvisGitHubRemoteScanner.swift').read_text()
        for text in ('"--method", "GET"', '"/user/repos?per_page=100',
                     '"--paginate"', 'GH_PROMPT_DISABLED', 'GH_HTTP_TIMEOUT',
                     'privateRepo', 'maximumDisplayed = 100'):
            self.assertIn(text, github)
        for forbidden in ('"auth", "token"', '"push"', '"fetch"', '"checkout"'):
            self.assertNotIn(forbidden, github)
        self.assertIn('startGitHubScanIfNeeded(id: id)', LIVE)
        self.assertIn('Date().timeIntervalSince($0) >= Self.githubRefreshSeconds', LIVE)
        self.assertIn('githubRefreshSeconds: TimeInterval = 600', LIVE)

    def test_vercel_read_only_project_and_deployment_status(self):
        vercel = (R/'macos/Sources/EidisMac/JarvisVercelRemoteScanner.swift').read_text()
        for text in ('["project", "ls", "--format=json"]',
                     '["ls", "--format=json"]', 'VERCEL_DISABLE_UPDATE_CHECK',
                     'JarvisVercelSnapshot', 'hasMoreDeployments'):
            self.assertIn(text,vercel)
        for forbidden in ('"deploy"', '"promote"', '"rollback"', '"remove"'):
            self.assertNotIn(forbidden,vercel)
        self.assertIn('startVercelScanIfNeeded(id: id)',LIVE)
        self.assertIn('Date().timeIntervalSince($0) >= Self.vercelRefreshSeconds',LIVE)
        self.assertIn('vercelRefreshSeconds: TimeInterval = 900', LIVE)
        self.assertIn('model.vercelSnapshot',COMMAND)

    def test_tv_readable_layout_and_provenance(self):
        for text in ('width < 1120', 'min(2.0, max(0.84', 'ScrollView(.vertical)',
                     'PROJECT OPERATIONS','GITHUB + LOCAL GIT','SOCIAL / DECHIVE.WIKI','YOUTUBE / CHANNEL INTELLIGENCE',
                     'Google 계정 연결','LOCAL GIT', 'LIVE CHECKS',
                     'RECORDED EVENTS', 'model.sourceChecks',
                     'model.recordedActivity', 'model.gitSnapshot', 'model.githubSnapshot',
                     '실제 기록 시각', 'GitHub는 로그인 계정의 API 결과'):
            self.assertIn(text,COMMAND)
        self.assertNotIn('fake statistics', COMMAND.lower())
        self.assertIn('<string>3.14.47</string>', INFO)
if __name__=='__main__':unittest.main()
