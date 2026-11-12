from jarvis.server import make_server
import webbrowser
import threading
import os

if __name__ == "__main__":
    server = make_server()
    url = "http://127.0.0.1:8765"
    print("JARVIS Lab v0.1 시작:", url)
    print("종료: 터미널에서 Ctrl+C. 외부 네트워크로 공개되지 않습니다.")
    if os.environ.get("JARVIS_NO_BROWSER") != "1":
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        server.RequestHandlerClass.store.close()
