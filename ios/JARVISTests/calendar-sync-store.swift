import Foundation

@main
struct MobileSyncStoreTests {
    @MainActor static func main() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-sync-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("calendar-v1.json")
        let store = JARVISCalendarStore(fileURL: path)
        let start = Date(timeIntervalSince1970: 1_840_000_000)
        let phoneID = UUID()
        let local = try store.save(JARVISCalendarRecord(
            id: phoneID, title: "아이폰 미팅", startAt: start, endAt: nil))
        let pending = try store.outgoingOperations()
        precondition(pending.count == 1)
        precondition((pending[0]["baseVersion"] as? NSNull) != nil)
        let remoteID = UUID()
        let response: [String: Any] = [
            "acknowledged": [phoneID.uuidString.lowercased()],
            "conflicts": [],
            "records": [
                macRecord(id: phoneID, title: "아이폰 미팅", date: start, version: "2026-11-24T00:20:45.024871Z"),
                macRecord(id: remoteID, title: "맥에서 추가한 일정", date: start.addingTimeInterval(1800),
                          version: "2026-11-24T00:21:01.128671Z")
            ]
        ]
        let merged = try store.acceptSync(response)
        precondition(merged.conflicts == 0)
        precondition(store.activeEntries.count == 2)
        precondition(store.activeEntries.contains { $0.id == phoneID && $0.endAt == nil })
        let afterFirstMerge = try store.outgoingOperations()
        precondition(afterFirstMerge.isEmpty)
        let reopened = JARVISCalendarStore(fileURL: path)
        precondition(reopened.activeEntries.count == 2)
        let afterReopening = try reopened.outgoingOperations()
        precondition(afterReopening.isEmpty)

        var changed = reopened.activeEntries.first(where: { $0.id == phoneID })!
        changed.title = "아이폰 재수정"
        try reopened.save(changed)
        let delta = try reopened.outgoingOperations()
        precondition(delta.count == 1)
        precondition(delta[0]["baseVersion"] as? String == "2026-11-24T00:20:45.024871Z")
        let conflict: [String: Any] = [
            "acknowledged": [],
            "conflicts": [["id": phoneID.uuidString.lowercased(), "reason": "changed_on_mac"]],
            "records": [
                macRecord(id: phoneID, title: "맥에서 동시 수정", date: start,
                          version: "2026-11-24T00:29:03.723781Z"),
                macRecord(id: remoteID, title: "맥에서 추가한 일정", date: start.addingTimeInterval(1800),
                          version: "2026-11-24T00:21:01.128671Z")
            ]
        ]
        let c = try reopened.acceptSync(conflict)
        precondition(c.conflicts == 1)
        precondition(reopened.activeEntries.first(where: { $0.id == phoneID })?.title == "아이폰 재수정")
        let afterConflict = try reopened.outgoingOperations()
        precondition(afterConflict.count == 1)
        precondition(afterConflict[0]["baseVersion"] as? String == "2026-11-24T00:20:45.024871Z")
        precondition(local.endAt == nil)
        print("PASS: native iPhone offline merge, Mac import, restart, optimistic edits and conflict preservation")
    }

    static func macRecord(id: UUID, title: String, date: Date, version: String) -> [String: Any] {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return ["id": id.uuidString.lowercased(), "title": title, "startAt": f.string(from: date),
                "endAt": NSNull(), "location": "", "notes": "", "reminderMinutes": NSNull(),
                "createdAt": version, "updatedAt": version, "deletedAt": NSNull()]
    }
}
