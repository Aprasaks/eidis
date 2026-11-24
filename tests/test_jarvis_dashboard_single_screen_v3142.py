from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
UI=(ROOT/'macos/Sources/EidisMac/JarvisCommandCenterView.swift').read_text()
ROUTER=(ROOT/'macos/Sources/EidisMac/JarvisLiveDashboard.swift').read_text()
OVERLAY=(ROOT/'macos/Sources/EidisMac/JarvisFullscreenOverlay.swift').read_text()
INFO=(ROOT/'macos/Resources/Info.plist').read_text()

class FixedViewportContract(unittest.TestCase):
    def test_no_outer_scroll_even_for_short_displays(self):
        outer=UI.split('    private func leftColumn(',1)[0]
        self.assertIn('GeometryReader { geometry in',outer)
        self.assertNotIn('ScrollView',outer)
        self.assertIn('let usableHeight = max(0, height - inputReserve - topInset)',outer)
        self.assertIn('.frame(width: width, height: height, alignment: .top)',outer)
        self.assertIn('.clipped()',outer)
        self.assertNotIn('Color.clear.frame(height: min(365',UI)
        self.assertIn('let projectHeight = remaining * 0.27',UI)
        self.assertIn('let metaHeight = remaining * 0.46',UI)
        self.assertIn('let youtubeHeight = remaining - projectHeight - metaHeight',UI)
        self.assertIn('frame(height: youtubeHeight)',UI)
        self.assertIn('let inputReserve: CGFloat = 116',UI)
        self.assertIn('JarvisCommandCenterView(model: liveDashboard, dialogue: dialogue)',OVERLAY)
        self.assertIn('JarvisOverviewGeometry.coreFrame(width: area.size.width, height: area.size.height)', OVERLAY)
    def test_every_long_list_scrolls_in_its_own_card(self):
        # Long operational logs still scroll inside their own cards; the new
        # compact social and YouTube profile summaries intentionally do not scroll.
        for name in ('projectsCard','gitCard','knowledgeCard',
                     'systemCard','activityCard','recordedCard'):
            segment=UI.split('    private func '+name+'(',1)[1].split('    private func ',1)[0]
            self.assertIn('ScrollView(.vertical)',segment,name)
            self.assertIn('.scrollIndicators(.visible)',segment,name)
        for name in ('metaCard','youtubeCard'):
            segment=UI.split('    private func '+name+'(',1)[1].split('    private func ',1)[0]
            self.assertNotIn('ScrollView(.vertical)',segment,name)
        self.assertIn('jarvis-command-real-checks',UI)
        self.assertIn('RECORDED EVENTS',UI)
    def test_exact_natural_language_opening_and_unmodified_sources(self):
        self.assertIn('"전체대시보드"',ROUTER)
        self.assertIn('"전체화면대시보드"',ROUTER)
        self.assertIn('"통합대시보드"',ROUTER)
        self.assertIn('"열어"',ROUTER)
        self.assertIn('"켜줘"',ROUTER)
        self.assertIn('return .show(.overview)',ROUTER)
        self.assertIn('<string>3.14.16</string>',INFO)
        self.assertIn('JarvisLoopingCore(videoURL: videoURL, compact: compactCore)',OVERLAY)

if __name__=='__main__': unittest.main()
