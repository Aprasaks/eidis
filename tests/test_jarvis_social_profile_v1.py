from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'macos' / 'Sources' / 'EidisMac'
ROUTER = (SRC / 'JarvisSocialProfileIntent.swift').read_text()
DIALOGUE = (SRC / 'JarvisOverlayConversation.swift').read_text()
BROWSER = (SRC / 'JarvisOverlayBrowser.swift').read_text()
CENTER = (SRC / 'JarvisCommandCenterView.swift').read_text()
# The SNS / YouTube channel monitor moved to its own file; check both.
CENTER += "\n" + (SRC / 'JarvisChannelMonitorView.swift').read_text()
META = (SRC / 'JarvisMetaChannels.swift').read_text()
INSTAGRAM = (SRC / 'JarvisMetaInstagramService.swift').read_text()
YOUTUBE = (ROOT / 'jarvis' / 'google_youtube.py').read_text()

class SocialProfileTests(unittest.TestCase):
    def test_pinned_social_pages_only(self):
        for url in ('www.instagram.com/dechive.wiki/', 'www.threads.com/@dechive.wiki',
                    'www.facebook.com/profile.php?id=1433547446509432'):
            self.assertIn(url, ROUTER)
        for term in ('인스타', '스레드', '페이스북', '유튜브', '열어', '검색', '게시'):
            self.assertIn(term, ROUTER)
        self.assertIn('channelID', DIALOGUE)
        self.assertIn('channel.url(youtubeChannelID: channelID)', DIALOGUE)
        self.assertIn('JarvisSocialProfile.parse(prompt)', DIALOGUE)
    def test_native_dashboard_default_with_optional_external_fallback(self):
        native = DIALOGUE.split('func openSocialProfile(', 1)[1].split('func closeNativeSocialDashboard', 1)[0]
        self.assertIn('socialDashboardChannel = channel', native)
        self.assertIn('_ = liveDashboard.hide()', native)
        self.assertNotIn('chrome.open', native)
        self.assertNotIn('onChromeWorkspaceOpen', native)
        overlay = (SRC / 'JarvisFullscreenOverlay.swift').read_text()
        self.assertIn('JarvisSocialDashboardView(channel: channel)', overlay)
        self.assertIn('dialogue.closeNativeSocialDashboard()', overlay)
        self.assertIn('func openExternalSocialProfile', DIALOGUE)
    def test_real_picture_sources_and_no_invented_metrics(self):
        self.assertIn('facebookDetails(', META)
        self.assertIn('threads_profile_picture_url', META)
        self.assertIn('profile_picture_url', INSTAGRAM)
        self.assertIn('thumbnail_url', YOUTUBE)
        self.assertIn('jarvis-social-open-\\(channel.rawValue)', CENTER)
        self.assertIn('jarvis-social-open-youtube', CENTER)
        for name in ('instagram', 'threads', 'facebook', 'youtube'):
            self.assertIn('case .' + name, ROUTER)
        self.assertIn('"—"', CENTER)
        self.assertIn('AsyncImage(url: url)', CENTER)
