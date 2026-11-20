from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
VAULT=(ROOT/'macos/Sources/EidisMac/JarvisKnowledgeVault.swift').read_text()
CONV=(ROOT/'macos/Sources/EidisMac/JarvisOverlayConversation.swift').read_text()
OVER=(ROOT/'macos/Sources/EidisMac/JarvisFullscreenOverlay.swift').read_text()
VOICE=(ROOT/'macos/Sources/EidisMac/ElevenLabsVoiceService.swift').read_text()
CMD=(ROOT/'macos/Sources/EidisMac/JarvisCommandEngine.swift').read_text()
SERVER=(ROOT/'jarvis/server.py').read_text()
STORAGE=(ROOT/'jarvis/storage.py').read_text()
PLIST=(ROOT/'macos/Resources/Info.plist').read_text()

class NativeVaultContract(unittest.TestCase):
    def test_local_vault_and_voice_safety(self):
        for marker in ('127.0.0.1:8765','URLSessionConfiguration.ephemeral',
                       'api/vault', 'api/vault/archive','api/vault/restore',
                       'sourceType:', 'func show(query:', 'func save(title:',
                       'func archive(id:', 'func restore(id:', 'func cancel()'):
            self.assertIn(marker,VAULT)
        self.assertNotIn('api.openai.com',VAULT)
        self.assertNotIn('api.anthropic.com',VAULT)
        self.assertIn('private static let summonGreeting = "데카이브, 자비스입니다."',VOICE)
        self.assertIn('replacingOccurrences(of: "DECHIVE", with: "데카이브"',CONV)
        self.assertIn("'데카이브'라고 발음하고 표현하세요",CMD)
    def test_on_demand_ui_and_command_routing(self):
        for marker in ('let vault = JarvisKnowledgeVault()', 'JarvisVaultIntent.parse(prompt)',
                       'private func handleVault(', '.saveCurrent:', 'browser.snapshotVisiblePage()',
                       'sourceType: "web_page"', 'sourceType: "assistant_response"',
                       'lastAssistantContent', 'vault.cancel()',
                       'if let intent = profileIntent, intent != .needsField'):
            self.assertIn(marker,CONV)
        for marker in ('@ObservedObject var vault: JarvisKnowledgeVault',
                       'knowledgeVaultPanel','jarvis-vault-panel','jarvis-vault-close',
                       'ForEach(JarvisKnowledgeVault.categoryOrder', 'item.evidenceLabel'):
            self.assertIn(marker,OVER)
        self.assertIn('vault: dialogue.vault',OVER)
        self.assertIn('"/api/vault"',SERVER)
        self.assertIn('"/api/vault/archive"',SERVER)
        self.assertIn('"/api/vault/restore"',SERVER)
        self.assertIn('CREATE TABLE IF NOT EXISTS vault_items',STORAGE)
        self.assertIn('CREATE UNIQUE INDEX IF NOT EXISTS vault_active_fingerprint_idx',STORAGE)
        self.assertIn('source_status',STORAGE)
        self.assertIn('<string>3.14.3</string>',PLIST)

if __name__=='__main__': unittest.main()
