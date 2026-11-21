"""Live publisher RSS and Swift-client smoke using disposable database."""
from pathlib import Path
from tempfile import TemporaryDirectory
from subprocess import run
from threading import Thread
from jarvis.server import make_server
from jarvis.storage import MemoryStore

def main():
    root=Path(__file__).resolve().parents[1]
    with TemporaryDirectory(prefix="jarvis-briefing-live-") as folder:
        exe=Path(folder)/"smoke"
        path=Path(folder)/"isolated.sqlite3"
        run(["swiftc","-parse-as-library","-o",str(exe),
             str(root/"macos/tests/briefing/main.swift"),
             str(root/"macos/Sources/EidisMac/JarvisMorningBriefing.swift")],check=True,timeout=45)
        server=make_server(port=0,db_path=path)
        thread=Thread(target=server.serve_forever,daemon=True);thread.start()
        try:
            run([str(exe),str(server.server_port)],check=True,timeout=50)
        finally:
            server.shutdown();server.server_close();thread.join(timeout=2)
            server.RequestHandlerClass.store.db.close()
        db=MemoryStore(path)
        try:
            assert db.db.execute("SELECT count(*) FROM morning_briefings").fetchone()[0]==1
            assert db.db.execute("SELECT count(*) FROM memories").fetchone()[0]==0
            assert db.db.execute("SELECT count(*) FROM vault_items").fetchone()[0]==0
            print("PASS: persisted report, no personal memory changes",flush=True)
        finally:db.db.close()

if __name__=="__main__":main()
