from pathlib import Path
import unittest
UI=(Path(__file__).resolve().parents[1]/"macos/Sources/EidisMac/JarvisCommandCenterView.swift").read_text()
class MainOverviewSources(unittest.TestCase):
    def test_overview_left_column_is_projects_meta_youtube(self):
        column=UI.split("private func leftColumn(",1)[1].split("private func centerColumn(",1)[0]
        self.assertIn("projectsCard(scale: scale).frame(height: projectHeight)",column)
        self.assertIn("metaCard(scale: scale).frame(height: metaHeight)",column)
        self.assertIn("youtubeCard(scale: scale).frame(height: youtubeHeight)",column)
        self.assertNotIn("gitCard(scale: scale)",column)
    def test_meta_and_youtube_do_not_share_card(self):
        meta=UI.split("private func metaCard(",1)[1].split("private func youtubeCard(",1)[0]
        youtube=UI.split("private func youtubeCard(",1)[1].split("private func knowledgeCard(",1)[0]
        self.assertIn("META / DECHIVE.WIKI",meta)
        self.assertIn("socialProfileRow(.instagram",meta)
        self.assertIn("socialProfileRow(.facebook",meta)
        self.assertIn("socialProfileRow(.threads",meta)
        self.assertIn('"jarvis-social-connection-settings"',meta)
        self.assertIn("jarvis-instagram-token-connect",meta)
        self.assertIn("model.instagramSnapshot",meta)
        self.assertIn("facebookSnapshot?.avatarURL",meta)
        self.assertIn("threadsSnapshot?.avatarURL",meta)
        self.assertIn('jarvis-meta-facebook-connect',meta)
        self.assertIn('jarvis-meta-threads-connect',meta)
        self.assertNotIn("model.youtubeSummary",meta)
        self.assertIn('panel("YOUTUBE / DECHIVE"',youtube)
        self.assertIn("model.youtubeSummary",youtube)
        self.assertIn("item.thumbnailUrl",youtube)
        self.assertIn("dialogue.openSocialProfile(.youtube)",youtube)
        self.assertIn("model.connectYouTube()",youtube)
        self.assertNotIn("instagramSnapshot",youtube)
        self.assertNotIn("Meta 토큰",youtube)
    def test_git_snapshot_remains_available_outside_left_overview(self):
        self.assertIn('private func gitCard(',UI)
        self.assertIn('metric("GITHUB"',UI)
if __name__=="__main__": unittest.main()
