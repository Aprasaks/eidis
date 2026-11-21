"""Manual actual-Qwen test. Never opens the user's production database."""
import pathlib, subprocess, tempfile, threading, sys
from jarvis.server import make_server
from jarvis.storage import MemoryStore
from jarvis import study

ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
    with tempfile.TemporaryDirectory(prefix="dechive-study-smoke-") as tmp:
        path=pathlib.Path(tmp)/"test.sqlite3"
        exe=pathlib.Path(tmp)/"study-smoke"
        subprocess.run(["swiftc","-parse-as-library","-o",str(exe),
                        str(ROOT/"macos/tests/thinking/study-live.swift"),
                        str(ROOT/"macos/Sources/EidisMac/JarvisThinkingCore.swift")],check=True)
        server=make_server(port=0,db_path=path)
        store=server.RequestHandlerClass.store
        store.add_memory("테스트 광고 전환율: 예시 자료에서 1,000회 노출, 20회 클릭, 실제 결제 여부 미확인.","synthetic")
        worker=threading.Thread(target=server.serve_forever,daemon=True)
        worker.start()
        try:
            subprocess.run([str(exe),str(server.server_port)],check=True,timeout=100)
        finally:
            server.shutdown()
            server.server_close()
            worker.join(timeout=2)
            store.db.close()
        reopened=MemoryStore(path)
        try:
            draft=study.get_draft(reopened,1)
            assert draft["result"].strip()
            assert draft["source_status"]=="ai_generated_unverified"
            assert draft["evidence"][0]["kind"]=="memory"
            assert reopened.list_thoughts()==[]
            print("PASS: persisted unverified draft, exact local source, existing facts unchanged", flush=True)
        finally:
            reopened.db.close()
if __name__=="__main__":
    main()
