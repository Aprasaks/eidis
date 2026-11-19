import json
import sqlite3
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from jarvis.storage import MemoryStore
from jarvis.server import make_server


class PersonalProfileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'memory.sqlite3'
        self.store = MemoryStore(self.path)

    def tearDown(self):
        self.store.close()
        self.temp.cleanup()

    def test_profile_kept_separate_from_existing_projects_and_memories(self):
        project = self.store.create_project('DECHIVE', '기존 프로젝트')
        task = self.store.add_project_task(project['id'], '기존 데이터')
        self.store.add_memory('사용자가 이전에 명시적으로 저장한 노트')
        self.store.upsert_profile('display_name', 'DECHIVE', source='user_approved_seed')
        self.store.upsert_profile('working_style', '결과를 검증한다')
        self.assertEqual(self.store.count_memories(), 1)
        self.assertEqual(len(self.store.list_projects()), 1)
        self.assertEqual(self.store.get_project(project['id'])['tasks'][0]['id'], task['id'])
        self.store.close()
        self.store = MemoryStore(self.path)
        profile = self.store.list_profile()
        self.assertEqual(len(profile), 2)
        self.assertEqual(next(p for p in profile if p['key'] == 'display_name')['source'], 'user_approved_seed')
        self.assertEqual(self.store.count_memories(), 1)
        self.assertEqual(self.store.db.execute('PRAGMA quick_check').fetchone()[0], 'ok')

    def test_update_and_forget_only_selected_field(self):
        self.store.upsert_profile('communication_style', '자연스러운 한국어')
        self.store.upsert_profile('values', '확인 가능한 사실을 중요하게 여긴다')
        self.store.upsert_profile('communication_style', '간결하게 이야기한다')
        self.assertEqual(len(self.store.list_profile()), 2)
        self.assertEqual(next(x['value'] for x in self.store.list_profile() if x['key']=='communication_style'), '간결하게 이야기한다')
        self.assertTrue(self.store.delete_profile('communication_style'))
        self.assertFalse(self.store.delete_profile('communication_style'))
        self.assertEqual(self.store.list_profile()[0]['key'], 'values')
        self.assertRaises(ValueError, self.store.delete_profile, 'password')

    def test_no_unconfirmed_guess_or_arbitrary_fields(self):
        for key in ('password', 'unknown', 'profile; DROP TABLE projects;', None):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.store.upsert_profile(key, 'something')
        with self.assertRaises(ValueError): self.store.upsert_profile('values', ' ', confirmed=True)
        with self.assertRaises(ValueError): self.store.upsert_profile('values', 'guess', confirmed=False)
        with self.assertRaises(ValueError): self.store.upsert_profile('values', 'guess', source='model_inferred')
        with self.assertRaises(ValueError): self.store.upsert_profile('values', 'x' * 351)
        self.assertEqual(self.store.list_profile(), [])

    def test_preexisting_db_schema_migrated_without_loss(self):
        self.store.close()
        connection = sqlite3.connect(self.path)
        connection.execute('DROP TABLE personal_profile')
        connection.execute("INSERT INTO memories (content, project, created_at) VALUES ('기존 메모','general','2026-11-20')")
        connection.commit(); connection.close()
        self.store = MemoryStore(self.path)
        self.assertEqual(self.store.count_memories(), 1)
        self.assertEqual(self.store.list_profile(), [])

    def test_local_api_read_write_forget_and_origin_restriction(self):
        server = make_server(port=0, db_path=Path(self.temp.name) / 'server.sqlite3')
        t = threading.Thread(target=server.serve_forever, daemon=True)
        t.start()
        root = f'http://127.0.0.1:{server.server_port}'
        def post(path, data, origin=None):
            headers = {'Content-Type':'application/json'}
            if origin: headers['Origin'] = origin
            request = Request(root+path, data=json.dumps(data).encode(),headers=headers,method='POST')
            with urlopen(request,timeout=4) as reply:
                return json.load(reply)
        try:
            with urlopen(root+'/api/profile') as reply:
                self.assertEqual(json.load(reply)['items'],[])
            entry = post('/api/profile',{'key':'values','value':'검증을 중시한다','source':'model_inferred'})['fact']
            self.assertEqual(entry['source'],'user_direct')
            self.assertEqual(entry['confirmed'],1)
            with urlopen(root+'/api/profile') as reply:
                self.assertEqual(json.load(reply)['items'][0]['value'],'검증을 중시한다')
            with self.assertRaises(HTTPError) as blocked:
                post('/api/profile',{'key':'values','value':'변조'}, origin='https://evil.example')
            self.assertEqual(blocked.exception.code,403)
            self.assertTrue(post('/api/profile/forget',{'key':'values'})['deleted'])
            with urlopen(root+'/api/profile') as reply:
                self.assertEqual(json.load(reply)['items'],[])
        finally:
            server.shutdown();server.server_close();server.RequestHandlerClass.store.close();t.join(timeout=4)


if __name__ == '__main__': unittest.main()
