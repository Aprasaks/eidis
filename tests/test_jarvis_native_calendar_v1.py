"""No Apple calendar: JARVIS-owned calendar CRUD, validation, HTTP isolation."""
import http.client
import json
import tempfile
import threading
import unittest
from pathlib import Path

from jarvis import calendar
from jarvis.storage import MemoryStore
from jarvis.server import make_server

START = '2026-12-02T06:00:00Z'
END = '2026-12-02T07:00:00Z'


class CalendarDataTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix='jarvis-calendar-test-')
        self.store = MemoryStore(Path(self.folder.name) / 'memory.sqlite3')

    def tearDown(self):
        self.store.db.close()
        self.folder.cleanup()

    def test_create_update_delete_persist_and_tombstone(self):
        db = self.store.db
        entry = calendar.create(db, {'title': '테스트 미팅', 'startAt': START, 'endAt': END, 'reminderMinutes': 10})
        self.assertEqual(len(calendar.listing(db)['items']), 1)
        self.assertEqual(entry['startAt'], START)
        self.assertEqual(entry['reminderMinutes'], 10)
        with self.assertRaises(ValueError):
            calendar.create(db, dict(id=entry['id'], title='중복', startAt=START, endAt=END))
        new = calendar.update(db, dict(id=entry['id'], title='변경된 미팅', startAt=START,
                                       endAt=END, expectedUpdatedAt=entry['updatedAt']))
        self.assertEqual(new['title'], '변경된 미팅')
        with self.assertRaises(ValueError):
            calendar.update(db, dict(id=entry['id'], title='오래된 편집', startAt=START,
                                     endAt=END, expectedUpdatedAt='2020-01-01T00:00:00Z'))
        calendar.delete(db, {'id': entry['id']})
        self.assertEqual(calendar.listing(db)['items'], [])
        self.assertEqual(db.execute('SELECT COUNT(*) FROM calendar_events').fetchone()[0], 1)
        with self.assertRaises(ValueError):
            calendar.delete(db, {'id': entry['id']})

    def test_validation_and_date_ranges(self):
        db = self.store.db
        for bad in (
            {'title': '', 'startAt': START, 'endAt': END},
            {'title': '시간 거꾸로', 'startAt': END, 'endAt': START},
            {'title': '지역 없음', 'startAt': '2026-12-02T15:00:00', 'endAt': END},
            {'title': '알림 오류', 'startAt': START, 'endAt': END, 'reminderMinutes': 999},
            {'title': '타입 오류', 'startAt': START, 'endAt': END, 'reminderMinutes': True},
            {'title': '비공개 필드', 'startAt': START, 'endAt': END, 'admin': True},
        ):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                calendar.create(db, bad)
        self.assertEqual(calendar.listing(db)['items'], [])
        a = calendar.create(db, {'title': '차트', 'startAt': START, 'endAt': END})
        self.assertEqual(len(calendar.listing(db, begin='2026-12-02T06:30:00Z')['items']), 1)
        self.assertEqual(len(calendar.listing(db, finish='2026-12-02T05:00:00Z')['items']), 0)
        with self.assertRaises(ValueError):
            calendar.listing(db, limit=201)
        self.assertTrue(a['id'])


class CalendarHTTPTests(unittest.TestCase):
    def test_local_routes_and_origin_enforcement(self):
        with tempfile.TemporaryDirectory(prefix='jarvis-calendar-http-') as folder:
            server = make_server(port=0, db_path=Path(folder) / 'server.sqlite3')
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                port = server.server_port
                def request(method, path, data=None, headers=None):
                    connection = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
                    h = dict(headers or {})
                    payload = json.dumps(data).encode() if data is not None else None
                    if payload is not None:
                        h['Content-Type'] = 'application/json'
                    connection.request(method, path, body=payload, headers=h)
                    reply = connection.getresponse()
                    status, body = reply.status, json.loads(reply.read())
                    connection.close()
                    return status, body
                status, data = request('GET', '/api/calendar')
                self.assertEqual(status, 200)
                self.assertEqual(data['items'], [])
                status, data = request('POST', '/api/calendar/create',
                                       {'title': '테스트 일정', 'startAt': START, 'endAt': END})
                self.assertEqual(status, 200)
                self.assertEqual(data['event']['title'], '테스트 일정')
                event_id = data['event']['id']
                status, data = request('GET', '/api/calendar?limit=10')
                self.assertEqual(status, 200)
                self.assertEqual(len(data['items']), 1)
                status, _ = request('POST', '/api/calendar/delete', {'id': event_id})
                self.assertEqual(status, 200)
                status, data = request('GET', '/api/calendar')
                self.assertEqual(data['items'], [])
                status, _ = request('GET', '/api/calendar', headers={'Origin': 'https://evil.example'})
                self.assertEqual(status, 403)
                status, _ = request('POST', '/api/calendar/create',
                                    {'title': '잘못된', 'startAt': 'no', 'endAt': END})
                self.assertEqual(status, 400)
            finally:
                server.shutdown()
                server.server_close()
                server.RequestHandlerClass.store.db.close()
                thread.join(5)


if __name__ == '__main__':
    unittest.main()
