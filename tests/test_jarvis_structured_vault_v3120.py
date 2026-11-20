import json
import sqlite3
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.request import Request,urlopen
from urllib.error import HTTPError

from jarvis.storage import MemoryStore
from jarvis.server import make_server

class StructuredVault(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.path=Path(self.temp.name)/'user.sqlite3'
        self.store=MemoryStore(self.path)
    def tearDown(self):
        self.store.close();self.temp.cleanup()

    def test_categories_tags_project_and_full_text_search(self):
        categories=[('블로그 아이디어','AI 글 구조 만들기','ideas'),
                    ('자비스 프로젝트 메모','작업 현황 보완','projects'),
                    ('엑셀 자료','참고 자료 XLOOKUP','references'),
                    ('AI 연구','오류 검증 분석','research'),
                    ('할 일 정리','체크리스트 만들기','tasks'),
                    ('기본 메모','오늘 확인 사항','notes')]
        for title,content,category in categories:
            item=self.store.save_vault(title=title,content=content,
                   category=self.store.classify_vault(title+' '+content),
                   project=self.store.vault_project(title+' '+content))
            self.assertEqual(item['category'],category)
            self.assertFalse(item['duplicate'])
        self.assertEqual(self.store.search_vault()['total'],6)
        self.assertEqual(self.store.search_vault(query='블로그')['total'],1)
        self.assertEqual(self.store.search_vault(query='AI')['total'],2)
        self.assertEqual(self.store.search_vault(category='research')['total'],1)
        self.assertEqual(self.store.search_vault(query='XLOOKUP')['items'][0]['category'],'references')
        self.assertEqual(self.store.search_vault(query='AI')['counts']['ideas'],1)
        self.assertEqual(self.store.search_vault(query='블로그')['items'][0]['tags'],['블로그','AI'])
        self.assertEqual(self.store.vault_project('데카이브 위키'), 'DECHIVE')
        self.assertEqual(self.store.vault_project('자비스 개발'), 'JARVIS')

    def test_duplicates_archiving_restoring_and_reopen(self):
        item=self.store.save_vault(title='아이디어 저장',content='블로그 아이디어 생각하기',category='ideas')
        second=self.store.save_vault(title='중복 제목',content='블로그 아이디어 생각하기',category='ideas')
        self.assertTrue(second['duplicate'])
        self.assertEqual(item['id'],second['id'])
        self.assertEqual(self.store.search_vault()['total'],1)
        self.assertTrue(self.store.archive_vault(item['id']))
        self.assertFalse(self.store.archive_vault(item['id']))
        self.assertEqual(self.store.search_vault()['total'],0)
        self.assertTrue(self.store.get_vault(item['id'])['archived'])
        self.store.close();self.store=MemoryStore(self.path)
        self.assertTrue(self.store.restore_vault(item['id']))
        self.assertFalse(self.store.restore_vault(item['id']))
        self.assertEqual(self.store.search_vault()['total'],1)
        self.assertEqual(self.store.db.execute('pragma quick_check').fetchone()[0],'ok')

    def test_escapes_wildcards_rejects_secrets_bad_links(self):
        self.store.save_vault(title='100% 정확',content='평가_원칙',category='notes')
        self.assertEqual(self.store.search_vault(query='%')['total'],1)
        self.assertEqual(self.store.search_vault(query='_')['total'],1)
        self.assertEqual(self.store.search_vault(query='!')['total'],0)
        for value in ('비밀번호: 1234', 'password: hello','sk-'+'a'*30,'ghp_'+'A'*40):
            with self.assertRaises(ValueError):
                self.store.save_vault(title='기밀',content=value)
        for value in ('file:///Users/a','http://example.com','https://user:pass@example.com'):
            with self.assertRaises(ValueError):
                self.store.save_vault(title='웹',content='본문',source_type='web_page',source_url=value)
        with self.assertRaises(ValueError):
            self.store.save_vault(title='웹',content='본문',source_type='web_page')
        with self.assertRaises(ValueError): self.store.search_vault(category='admin')
        with self.assertRaises(ValueError): self.store.archive_vault(True)
        self.assertEqual(self.store.search_vault()['total'],1)

    def test_old_schema_and_projects_survive_additive_migration(self):
        p=self.store.create_project('DECHIVE','기존 목표')
        t=self.store.add_project_task(p['id'],'기존 작업')
        self.store.upsert_profile('display_name','데카이브')
        self.store.add_memory('기존 명시적 메모')
        self.store.close();conn=sqlite3.connect(self.path)
        conn.execute('DROP TABLE vault_items');conn.commit();conn.close()
        self.store=MemoryStore(self.path)
        self.assertEqual(len(self.store.list_projects()),1)
        self.assertEqual(self.store.get_project(p['id'])['tasks'][0]['id'],t['id'])
        self.assertEqual(self.store.count_memories(),1)
        self.assertEqual(self.store.list_profile()[0]['value'],'데카이브')
        self.assertEqual(self.store.search_vault()['total'],0)

    def test_api_origin_save_search_archive_restore(self):
        httpd=make_server(port=0,db_path=Path(self.temp.name)/'http.sqlite3')
        thread=threading.Thread(target=httpd.serve_forever,daemon=True);thread.start()
        root=f'http://127.0.0.1:{httpd.server_port}'
        def post(route,body,origin=None):
            headers={'Content-Type':'application/json'}
            if origin:headers['Origin']=origin
            req=Request(root+route,data=json.dumps(body).encode(),headers=headers,method='POST')
            with urlopen(req,timeout=5) as response:return json.load(response)
        try:
            item=post('/api/vault',{'title':'블로그 아이디어','content':'AI 검증 사례 정리'})['item']
            self.assertEqual(item['category'],'ideas')
            self.assertEqual(item['source_type'],'user_text')
            self.assertEqual(item['source_status'],'user_supplied')
            with urlopen(root+'/api/vault?query=AI') as response:
                self.assertEqual(json.load(response)['total'],1)
            with urlopen(root+'/api/vault/item?id='+str(item['id'])) as response:
                self.assertEqual(json.load(response)['item']['title'],'블로그 아이디어')
            with self.assertRaises(HTTPError) as err:
                post('/api/vault',{'title':'유해','content':'외부'},origin='https://evil.example')
            self.assertEqual(err.exception.code,403)
            self.assertTrue(post('/api/vault/archive',{'id':item['id']})['archived'])
            with urlopen(root+'/api/vault') as response:
                self.assertEqual(json.load(response)['total'],0)
            self.assertTrue(post('/api/vault/restore',{'id':item['id']})['restored'])
            with urlopen(root+'/api/vault') as response:
                self.assertEqual(json.load(response)['total'],1)
        finally:
            httpd.shutdown();httpd.server_close();httpd.RequestHandlerClass.store.close();thread.join(timeout=4)

if __name__=='__main__':unittest.main()
