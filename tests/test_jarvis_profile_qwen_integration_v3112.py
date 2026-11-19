from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
SERVICE=(ROOT/'macos/Sources/EidisMac/JarvisPersonalProfile.swift').read_text()
CHAT=(ROOT/'macos/Sources/EidisMac/JarvisOverlayConversation.swift').read_text()
SERVER=(ROOT/'jarvis/server.py').read_text()
STORAGE=(ROOT/'jarvis/storage.py').read_text()
PACKAGE=(ROOT/'macos/scripts/package-app.sh').read_text()

class ProfileIntegrationContract(unittest.TestCase):
    def test_local_profile_context_not_saved_transcript(self):
        for part in ('http://127.0.0.1:8765', '"api/profile"',
                     '"api/profile/forget"', 'URLSessionConfiguration.ephemeral',
                     'func contextForQwen()', 'func recall()',
                     'func set(_ key:', 'func forget(_ key:',
                     'confirmed == 1', 'source:', 'func cancel()'):
            self.assertIn(part,SERVICE)
        for part in ('let personalProfile = JarvisPersonalProfile()',
                     'JarvisPersonalProfile.parse(prompt)',
                     'contextForQwen()', 'JarvisCommand.systemInstructions',
                     'profileContext.isEmpty', 'personalProfile.cancel()', 'isMemoryAnswer = JarvisPersonalProfile.parse(prompt) == .recall'):
            self.assertIn(part,CHAT)
        self.assertNotIn('UserDefaults.standard.set(', SERVICE)
        self.assertNotIn('api.openai.com', SERVICE)
        self.assertNotIn('api.anthropic.com', SERVICE)
        self.assertNotIn('FileHandle(forWritingTo:', SERVICE)
    def test_only_confirmed_user_controlled_fields(self):
        for part in ('personal_profile', 'user_direct', 'user_approved_seed',
                     'confirmed INTEGER NOT NULL', 'confirmed=excluded.confirmed',
                     'delete_profile', 'upsert_profile',
                     '"display_name"', '"working_style"', '"assistant_role"',
                     '"goals"'):
            self.assertIn(part,STORAGE)
        for part in ('"/api/profile"', '"/api/profile/forget"',
                     'source="user_direct", confirmed=True', '"profile_count"'):
            self.assertIn(part,SERVER)
        self.assertIn('if not self._same_origin()',SERVER)
        self.assertIn('security find-identity', PACKAGE)
        self.assertIn('anchor apple generic',PACKAGE)
    def test_secret_guard_and_no_unintended_memory_write(self):
        for part in ('"비밀번호"','"주민번호"', '"api key"'):
            self.assertIn(part,STORAGE)
        self.assertIn('return .needsField',SERVICE)
        self.assertIn('사용자가 확인하지 않은 프로필은 저장하지 않습니다.',STORAGE)
        self.assertIn('기억할 프로필 항목을 구체적으로',CHAT)
        self.assertIn('저장한 사용자 프로필입니다.', SERVICE)

if __name__=='__main__':unittest.main()
