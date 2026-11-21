"""Manual real-world search smoke. Uses a disposable SQLite database only."""
from pathlib import Path
from tempfile import TemporaryDirectory
import json
import threading
import time
from urllib.request import urlopen, Request

from jarvis.server import make_server
from jarvis.storage import MemoryStore
from jarvis import research


def main():
    with TemporaryDirectory(prefix="dechive-research-live-") as temp:
        path=Path(temp)/"research.sqlite3"
        server=make_server(port=0,db_path=path)
        thread=threading.Thread(target=lambda: server.serve_forever(poll_interval=.05),daemon=True)
        thread.start()
        base=f"http://127.0.0.1:{server.server_port}"
        try:
            payload=json.dumps({"query":"Python official documentation"}).encode()
            req=Request(base+"/api/research/submit",data=payload,
                        headers={"Content-Type":"application/json"})
            with urlopen(req,timeout=4) as response:
                id=json.load(response)["job"]["id"]
            print("REAL_SEARCH_JOB",id,flush=True)
            end=time.monotonic()+50
            last=""
            while time.monotonic()<end:
                with urlopen(base+"/api/research/job?id="+str(id),timeout=4) as response:
                    result=json.load(response)
                if result["progress"]!=last:
                    print("STATE",result["state"],result["progress"],flush=True)
                    last=result["progress"]
                if result["state"] not in ("queued","running"):
                    break
                time.sleep(.25)
            else:raise RuntimeError("real search timed out")
            total=len(result["sources"])
            fetched=[x for x in result["sources"] if x["state"]=="retrieved"]
            print("REAL_REPORT",result["state"],"hits",total,"fetched",len(fetched),flush=True)
            for source in result["sources"][:4]:
                print("REAL_SOURCE",source["rank"],source["domain"],source["state"],source["url"][:120],flush=True)
            assert total>=1
            assert len(fetched)>=1
            assert "원문 수집" in result["report"]
            assert "https://www.python.org/" in result["report"]
            assert "독립 검증되지 않았습니다" in result["report"]
            assert not server.RequestHandlerClass.store.list_thoughts()
            assert not server.RequestHandlerClass.store.list_projects()
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
            server.RequestHandlerClass.store.db.close()
        store=MemoryStore(path)
        try:
            saved=research.get_job(store,id)
            assert len(saved["sources"])==total
            assert saved["report"]==result["report"]
            print("PASS REAL WEB SEARCH AND PERSISTENCE",flush=True)
        finally:store.db.close()

if __name__=="__main__":main()
