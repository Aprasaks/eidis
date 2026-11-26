import unittest, json, subprocess, shutil, re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
M=(ROOT/"macos/Sources/EidisMac/JarvisMacNearbyCalendar.swift").read_text()
V=(ROOT/"ios/JARVIS/Sources/JARVISMobileDashboardView.swift").read_text()
P=Path.home()/"Documents/ChatGPT/Dechive Site/scripts/jarvis-knowledge-publish-approved.mjs"
class PublishOrder(unittest.TestCase):
    def test_display_order_and_guard(self):
        self.assertIn('"topicNumber":topic.number',M)
        self.assertIn("if a != b { return a < b }",M)
        self.assertIn("guard isFirstReview(review) else { return }",V)
        self.assertIn("발행 대기 순서",V)
        self.assertIn("review.numberedTitle",V)
    @unittest.skipUnless(shutil.which("node") and P.exists(),"Node and publisher required")
    def test_actual_order_guard_with_fake_cms(self):
        s=P.read_text()
        start=s.index("const catalog",s.index("// Check the live draft queue"))
        end=re.search(r"const\s*\{\s*_id\s*,",s[start:])
        self.assertIsNotNone(end)
        block=s[start:start+end.start()]
        transaction=re.search(r"await\s+client\s*\.\s*transaction\s*\(",s)
        self.assertIsNotNone(transaction)
        self.assertLess(s.index("EARLIER_REVIEW_PENDING"),transaction.start())
        catalog=json.loads((ROOT/"docs/knowledge/knowledge-catalog.json").read_text())
        code="""
const assert=require("node:assert/strict");
const catalog=JSON.parse(process.argv[1]);
const fs={readFileSync:()=>JSON.stringify(catalog)};
const path={join:()=>""}; const os={homedir:()=>""};
const fail=m=>{throw Error(m)};
const slugOf=t=>t.slug ?? "knowledge-"+t.code.toLowerCase();
const test=async(slug,queued)=>{
 const client={fetch:async(q,p)=>queued.filter(x=>p.earlier.includes(x)).map(_id=>({_id}))};
 const process={exit:n=>{throw n}};
 try { """+block+""" return "allowed"; } catch(e){ if(e===4) return "blocked"; throw e; }
};
(async()=>{const a=slugOf(catalog.topics[37]),b=slugOf(catalog.topics[38]),c=slugOf(catalog.topics[39]);
 assert.equal(await test(b,[a,b]),"blocked");
 assert.equal(await test(a,[a,b]),"allowed");
 assert.equal(await test(b,[b]),"allowed");
 assert.equal(await test(c,[b]),"blocked");
 assert.equal(await test(c,[]),"allowed");
 console.log("PASS: earlier review blocks later approval; no CMS mutation");
})().catch(e=>{console.error(e);process.exit(1)});
"""
        subprocess.run(["node","-e",code,json.dumps(catalog)],check=True,timeout=20)
if __name__=="__main__": unittest.main()
