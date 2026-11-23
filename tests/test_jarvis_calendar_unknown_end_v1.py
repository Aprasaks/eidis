"""No fabricated duration: preserve old Mac schedule rows while migrating."""
import sqlite3
import tempfile
import unittest
from pathlib import Path
from jarvis import calendar
from jarvis.storage import MemoryStore


class UnknownEndCalendarTests(unittest.TestCase):
    def test_create_modify_query_and_remove_unknown_end(self):
        with tempfile.TemporaryDirectory() as folder:
            store = MemoryStore(Path(folder) / 'calendar.sqlite3')
            db = store.db
            created = calendar.create(db, {
                'title': '종료 미정 회의', 'startAt': '2026-12-08T05:30:00Z',
                'endAt': None, 'location': '군산', 'notes': '회의 준비',
            })
            self.assertIsNone(created['endAt'])
            self.assertEqual(created['location'], '군산')
            # A no-end event is returned even when querying later times,
            # because its end is unknown rather than a made-up hour.
            later = calendar.listing(db, begin='2026-12-08T08:00:00Z')
            self.assertEqual([e['id'] for e in later['items']], [created['id']])
            self.assertEqual(calendar.listing(db, finish='2026-12-08T04:00:00Z')['items'], [])
            updated = calendar.update(db, {
                'id': created['id'], 'title': '종료 미정 회의',
                'startAt': created['startAt'], 'endAt': '2026-12-08T09:00:00Z',
                'location': created['location'], 'notes': created['notes'],
                'expectedUpdatedAt': created['updatedAt'],
            })
            self.assertEqual(updated['endAt'], '2026-12-08T09:00:00Z')
            self.assertTrue(calendar.delete(db, {'id': created['id']})['deleted'])
            self.assertEqual(calendar.listing(db)['items'], [])
            store.db.close()

    def test_migration_from_previous_required_end_schema_preserves_rows(self):
        with tempfile.TemporaryDirectory() as folder:
            filename = Path(folder) / 'old.sqlite3'
            conn = sqlite3.connect(filename)
            conn.execute('''CREATE TABLE calendar_events (
                id TEXT PRIMARY KEY, title TEXT NOT NULL,
                start_at TEXT NOT NULL, end_at TEXT NOT NULL,
                location TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '',
                reminder_minutes INTEGER, created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL, deleted_at TEXT)''')
            conn.execute('''INSERT INTO calendar_events VALUES
                ('11111111-1111-4111-8111-111111111111','오래된 일정',
                '2026-11-25T06:00:00Z','2026-11-25T07:00:00Z',
                '서울','기존 상세 기록',NULL,
                '2026-11-24T00:00:00Z','2026-11-24T00:00:00Z',NULL)''')
            conn.commit()
            conn.close()
            store = MemoryStore(filename)
            records = calendar.listing(store.db)['items']
            self.assertEqual(len(records), 1)
            self.assertEqual(records[0]['title'], '오래된 일정')
            self.assertEqual(records[0]['notes'], '기존 상세 기록')
            self.assertEqual(records[0]['endAt'], '2026-11-25T07:00:00Z')
            columns = {r[1]: r[3] for r in store.db.execute('PRAGMA table_info(calendar_events)')}
            self.assertEqual(columns['end_at'], 0)
            new = calendar.create(store.db, {
                'title': '새 미정 일정', 'startAt': '2026-11-26T03:00:00Z',
                'endAt': None,
            })
            self.assertIsNone(new['endAt'])
            store.db.close()
            reopened = MemoryStore(filename)
            self.assertEqual(len(calendar.listing(reopened.db)['items']), 2)
            reopened.db.close()

if __name__ == '__main__':
    unittest.main()
