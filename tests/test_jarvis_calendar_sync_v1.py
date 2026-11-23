"""Synchronized first-party events: tombstones and conflicting edits never overwritten."""
import tempfile
import unittest
import uuid
from pathlib import Path
from jarvis.storage import MemoryStore
from jarvis import calendar

START = '2026-12-02T10:00:00Z'


class CalendarMergeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='jarvis-nearby-')
        self.store = MemoryStore(Path(self.temp.name) / 'memory.sqlite3')
        self.db = self.store.db

    def tearDown(self):
        self.db.close()
        self.temp.cleanup()

    def event(self, title, id=None, deletedAt=None):
        return dict(id=id or str(uuid.uuid4()), title=title,
                    startAt=START, endAt=None, location='군산', notes='실제 계획',
                    reminderMinutes=None, deletedAt=deletedAt)

    def sync(self, changes):
        return calendar.sync_changes(self.db, {'operations': changes})

    def test_two_devices_create_update_and_delete_tombstone(self):
        mac = calendar.create(self.db, {k: v for k, v in self.event('맥 등록 일정').items() if k != 'deletedAt'})
        self.assertEqual(len(calendar.sync_snapshot(self.db)), 1)
        phone = self.event('아이폰 등록 일정')
        added = self.sync([{'record': phone, 'baseVersion': None}])
        self.assertEqual(added['acknowledged'], [phone['id']])
        self.assertEqual(len(added['records']), 2)
        phone_mac = next(x for x in added['records'] if x['id'] == phone['id'])
        changed = self.event('아이폰에서 수정', id=phone['id'])
        updated = self.sync([{'record': changed, 'baseVersion': phone_mac['updatedAt']}])
        self.assertEqual(updated['conflicts'], [])
        entry = next(x for x in updated['records'] if x['id'] == phone['id'])
        self.assertEqual(entry['title'], '아이폰에서 수정')
        deleted = self.event('아이폰에서 수정', id=phone['id'], deletedAt='2026-12-03T00:00:00Z')
        removed = self.sync([{'record': deleted, 'baseVersion': entry['updatedAt']}])
        self.assertEqual(removed['acknowledged'], [phone['id']])
        self.assertIsNotNone(next(x for x in removed['records'] if x['id'] == phone['id'])['deletedAt'])
        self.assertEqual(len(calendar.listing(self.db)['items']), 1)
        self.assertEqual(calendar.listing(self.db)['items'][0]['id'], mac['id'])

    def test_stale_phone_edit_conflicts_and_mac_record_preserved(self):
        start = calendar.create(self.db, {k: v for k, v in self.event('원본').items() if k != 'deletedAt'})
        calendar.update(self.db, dict(id=start['id'], title='맥에서 수정', startAt=START,
                                      endAt=None, expectedUpdatedAt=start['updatedAt']))
        result = self.sync([{'record': self.event('아이폰에서 동시 수정', id=start['id']),
                             'baseVersion': start['updatedAt']}])
        self.assertEqual(result['acknowledged'], [])
        self.assertEqual(result['conflicts'][0]['id'], start['id'])
        self.assertEqual(calendar.listing(self.db)['items'][0]['title'], '맥에서 수정')

    def test_create_delete_offline_before_first_pair_creates_no_ghost(self):
        gone = self.event('만들고 바로 삭제', deletedAt='2026-11-30T00:00:00Z')
        result = self.sync([{'record': gone, 'baseVersion': None}])
        self.assertEqual(result['acknowledged'], [gone['id']])
        self.assertEqual(result['records'], [])

    def test_duplicate_ids_and_invalid_payload_rejected(self):
        event = self.event('하나')
        with self.assertRaises(ValueError):
            self.sync([{'record': event, 'baseVersion': None},
                       {'record': event, 'baseVersion': None}])
        self.assertEqual(calendar.listing(self.db)['items'], [])

if __name__ == '__main__':
    unittest.main()
