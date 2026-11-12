import json
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError

from jarvis.engine import JarvisEngine, CAPABILITIES
from jarvis.storage import MemoryStore
from jarvis.server import make_server


class JarvisTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = MemoryStore(Path(self.tmp.name) / 'memory.sqlite3')
        self.engine = JarvisEngine(self.store)

    def tearDown(self):
        self.store.close()
        self.tmp.cleanup()

    def test_wake(self):
        out = self.engine.handle('자비스?')
        self.assertEqual(out['mode'], 'orb')
        self.assertEqual(out['action'], 'wake')
        self.assertEqual(out['spoken'], '네, 듣고 있습니다.')

    def test_dashboard(self):
        self.assertEqual(self.engine.handle('자비스 대시보드 띄워')['mode'], 'dashboard')
        self.assertEqual(self.engine.handle('자비스 대시보드 좀 바꿔')['mode'], 'variants')

    def test_explicit_memory(self):
        self.engine.handle('자비스 기억해: 입자 원은 유지')
        self.assertEqual(self.store.recent_memories()[0]['content'], '입자 원은 유지')
        self.assertIn('입자 원은 유지', self.engine.handle('저장한 기억 보여')['spoken'])

    def test_does_not_fabricate(self):
        out = self.engine.handle('자비스, 내 맥에서 중요한 파일 지워')
        self.assertFalse(out['executed'])
        self.assertEqual(out['action'], 'unsupported')
        self.assertEqual(CAPABILITIES['mac_control'], 'not_connected')

    def test_screen_is_preview_only(self):
        out = self.engine.handle('지금 내 화면 봐')
        self.assertEqual(out['mode'], 'screen')
        self.assertFalse(out['executed'])
        self.assertEqual(CAPABILITIES['vision_understanding'], 'not_connected')

    def test_transcripts_not_saved_to_memory(self):
        self.engine.handle('자비스, 비밀번호가 뭐였더라')
        self.assertEqual(self.store.recent_memories(), [])

    def test_validation(self):
        for t in ['', '  ', 'a' * 2001]:
            with self.assertRaises(ValueError): self.engine.handle(t)

    def test_api_and_foreign_origin_blocked(self):
        self.store.close()
        db = Path(self.tmp.name) / 'http-test.sqlite3'
        httpd = make_server(port=0, db_path=db)
        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()
        url = f'http://127.0.0.1:{httpd.server_port}'
        try:
            with urlopen(url + '/api/status') as result:
                data = json.load(result)
            self.assertEqual(data['version'], '0.1.0')
            self.assertEqual(data['capabilities']['cloud'], 'not_connected')
            body = json.dumps({'text':'자비스?'}).encode()
            req = Request(url + '/api/command',data=body,method='POST', headers={'Content-Type':'application/json','Origin':url})
            with urlopen(req) as result:
                self.assertEqual(json.load(result)['action'],'wake')
            evil = Request(url + '/api/command',data=body,method='POST', headers={'Content-Type':'application/json','Origin':'https://random.example'})
            with self.assertRaises(HTTPError) as cm:
                urlopen(evil)
            self.assertEqual(cm.exception.code,403)
        finally:
            httpd.shutdown();httpd.server_close();httpd.RequestHandlerClass.store.close();thread.join(timeout=3)


if __name__ == '__main__':
    unittest.main()
