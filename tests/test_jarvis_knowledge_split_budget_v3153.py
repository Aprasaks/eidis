import unittest, tempfile, subprocess, shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
A=(ROOT/'macos/Sources/EidisMac/JarvisAgentTerminalBay.swift').read_text()
C=(ROOT/'macos/Sources/EidisMac/JarvisKnowledgeCatalog.swift').read_text()
class SplitBudget(unittest.TestCase):
    def test_goal_and_separate_reservations(self):
        self.assertIn("staged.count < JarvisKnowledgeDailyBudget.limit",A)
        self.assertIn("reserveRepair(topicCode: topic.code)",A)
        self.assertIn("검토 등록 3편 목표 달성",A)
        self.assertIn("recovery.lock",A)
    @unittest.skipUnless(shutil.which("swift"),"Swift required")
    def test_real_budget(self):
        source=C.split("enum JarvisKnowledgeDailyBudget {")[1].split("struct JarvisKnowledgePublicArticle")[0]
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"test.swift"
            p.write_text('import Foundation\nimport Darwin\nstruct JarvisKnowledgeCatalog { static var root: URL { URL(fileURLWithPath:"/nonexistent") } }\nenum JarvisKnowledgeDailyBudget {'+source+'let B = JarvisKnowledgeDailyBudget.self\nlet root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)\ndefer { try? FileManager.default.removeItem(at: root) }\nlet format = ISO8601DateFormatter()\nlet old = format.date(from:"2026-11-27T00:30:00+09:00")!\nlet next = format.date(from:"2026-11-28T00:00:00+09:00")!\nfunc check(_ value: Bool, _ message: String) { precondition(value,message) }\nfor n in 1...3 { let v = try B.reserve(root:root,at:old); check(v == n,"old starts") }\nlet oldRepair = try B.reserveRepair(topicCode:"K03-07",root:root,at:old)\ncheck(!oldRepair && B.used(root:root,at:old)==3,"historical budget preserved")\nfor n in 1...3 {\n let v = try B.reserve(root:root,at:next); check(v == n,"new starts")\n let ok = try B.reserveRepair(topicCode:"K03-0"+String(n),root:root,at:next); check(ok,"independent repair")\n let again = try B.reserveRepair(topicCode:"K03-0"+String(n),root:root,at:next); check(!again,"duplicate blocked")\n}\nlet extra = try B.reserve(root:root,at:next)\nlet extraRepair = try B.reserveRepair(topicCode:"K03-04",root:root,at:next)\ncheck(extra == nil && !extraRepair,"caps enforced")\ncheck(B.used(root:root,at:next)==3 && B.repairUsed(root:root,at:next)==3,"independent counters")\nprint("PASS: previous day unchanged; 3 new + 3 separate repairs; duplicates and fourth runs rejected")\n')
            subprocess.run(["swift",str(p)],check=True,timeout=45)
if __name__=="__main__": unittest.main()
