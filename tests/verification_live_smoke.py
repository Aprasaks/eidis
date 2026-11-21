"""Actual local Qwen source-quote verification on a disposable DB only."""
from pathlib import Path
import subprocess
import tempfile
import threading

from jarvis.server import make_server
from jarvis.storage import MemoryStore
from jarvis import verification

SRC1="Python is a programming language that lets you work quickly and integrate systems more effectively."
SRC2="Python is an interpreted, object-oriented, high-level programming language with dynamic semantics."

def main():
    root=Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="dechive-verification-live-") as folder:
        path=Path(folder)/"test.sqlite3"
        exe=Path(folder)/"verification-smoke"
        subprocess.run(["swiftc","-parse-as-library","-o",str(exe),
            str(root/"macos/tests/research/verification-live.swift"),
            str(root/"macos/Sources/EidisMac/JarvisResearchVerification.swift"),
            str(root/"macos/Sources/EidisMac/JarvisThinkingCore.swift")],check=True,timeout=50)
        server=make_server(port=0,db_path=path)
        store=server.RequestHandlerClass.store
        with store.db:
            job=store.db.execute(
                "INSERT INTO research_jobs(query,state,requested_at,updated_at) "
                "VALUES(?,'completed',?,?)",("What is Python?","2026-11-20T06:00:00+00:00",
                                              "2026-11-20T06:00:00+00:00")
            ).lastrowid
            for rank,content,domain in [(1,SRC1,"python.org"),(2,SRC2,"docs.python.org")]:
                store.db.execute(
                    "INSERT INTO research_sources(job_id,rank,title,url,domain,state,checked_at,content_excerpt) "
                    "VALUES(?,?,?,?,?,'retrieved',?,?)",
                    (job,rank,f"Python official excerpt {rank}",f"https://{domain}/",domain,
                     "2026-11-20T06:00:00+00:00",content)
                )
        thread=threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        try:
            subprocess.run([str(exe),str(server.server_port)],check=True,timeout=115)
        finally:
            server.shutdown();server.server_close()
            thread.join(timeout=2)
            store.db.close()
        reopened=MemoryStore(path)
        try:
            result=verification.get_job(reopened,1)
            assert result["state"]=="draft",result["state"]
            assert result["report"]
            assert result["result"]["claims"]
            for claim in result["result"]["claims"]:
                for ref in claim["evidence"]:
                    source=reopened.db.execute(
                        "SELECT content_excerpt FROM research_sources WHERE job_id=? AND rank=?",
                        (job,ref["rank"])
                    ).fetchone()[0]
                    assert ref["quote"] in source,(ref,source)
            assert reopened.db.execute("SELECT COUNT(*) FROM thought_records").fetchone()[0]==0
            assert reopened.db.execute("SELECT COUNT(*) FROM vault_items").fetchone()[0]==0
            print("PASS: persisted exact quotes with right source numbers; no personal data changed",flush=True)
        finally:
            reopened.db.close()


if __name__=="__main__":main()
