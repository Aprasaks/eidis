import Foundation

@main
struct CalendarStoreTests {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-calendar-store-tests-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("calendar-v1.json")
        let store = JARVISCalendarStore(fileURL: path)
        precondition(store.activeEntries.isEmpty)
        let start = Date(timeIntervalSince1970: 1_840_000_000)
        let entry = JARVISCalendarRecord(title: "Sample, test only", startAt: start, endAt: start.addingTimeInterval(3600))
        let saved = try store.save(entry)
        precondition(saved.id == entry.id)
        precondition(store.activeEntries.count == 1)
        let reopened = JARVISCalendarStore(fileURL: path)
        precondition(reopened.activeEntries.count == 1 && reopened.activeEntries[0].title == "Sample, test only")
        var updated = saved
        updated.title = "Updated test record"
        try reopened.save(updated)
        let nextReload = JARVISCalendarStore(fileURL: path)
        precondition(nextReload.activeEntries[0].title == "Updated test record")
        try nextReload.delete(entry.id)
        precondition(nextReload.activeEntries.isEmpty)
        let afterDeletion = JARVISCalendarStore(fileURL: path)
        precondition(afterDeletion.activeEntries.isEmpty && afterDeletion.entries.count == 1)
        precondition(afterDeletion.entries.first?.deletedAt != nil)
        try Data("bad JSON".utf8).write(to: path, options: .atomic)
        let damaged = JARVISCalendarStore(fileURL: path)
        precondition(damaged.errorMessage != nil)
        do {
            try damaged.save(entry)
            fatalError("should not overwrite damaged file")
        } catch is JARVISCalendarError { }
        let corruptedBytes = try Data(contentsOf: path)
        precondition(String(decoding: corruptedBytes, as: UTF8.self) == "bad JSON")
        print("PASS: JARVIS calendar add/reload/edit/reload/tombstone/corrupt-file preservation")
    }
}
