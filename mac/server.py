# Launches the game on the watch with devicectl, reads its console STATE lines and forwards them to the page as Server-Sent Events.
# Run: python3 mac/server.py, then open http://localhost:8765
import http.server
import json
import pathlib
import subprocess
import sys
import tempfile
import threading
import time

PAGE = pathlib.Path(__file__).with_name("index.html")
BUNDLE = "com.spidergy07.watchfishing"
state = {"data": "{}", "seq": 0}
cond = threading.Condition()


def publish(line):
    try:
        json.loads(line)
    except ValueError:
        return
    with cond:
        state["data"] = line
        state["seq"] += 1
        cond.notify_all()


def find_watch():
    with tempfile.NamedTemporaryFile(suffix=".json") as f:
        subprocess.run(["xcrun", "devicectl", "list", "devices", "--json-output", f.name],
                       capture_output=True, check=True)
        devices = json.load(open(f.name))["result"]["devices"]
    for d in devices:
        hw = d.get("hardwareProperties", {})
        if hw.get("platform") == "watchOS" and hw.get("reality") == "physical":
            return d["identifier"]
    sys.exit("No paired Apple Watch found. Open Device Hub and check that your watch is listed.")


def pump(watch):
    while True:
        p = subprocess.Popen(
            ["xcrun", "devicectl", "device", "process", "launch", "--console", "--terminate-existing",
             "--device", watch, BUNDLE],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        last = [time.time()]

        # an app suspended while the watch screen was off never sends again, so relaunch after a quiet spell
        def watchdog():
            while p.poll() is None:
                if time.time() - last[0] > 8:
                    print("No signal from the watch for 8 s, relaunching. Raise your wrist so the screen is on.")
                    p.kill()
                    return
                time.sleep(1)

        threading.Thread(target=watchdog, daemon=True).start()
        for line in p.stdout:
            if line.startswith("STATE "):
                last[0] = time.time()
                publish(line[6:].strip())
            elif "unlocked" in line:
                print("Unlock the watch, the game will relaunch in a moment.")
            else:
                print("watch:", line.rstrip())
        p.wait()
        time.sleep(3)


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/events":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            seq = -1
            try:
                while True:
                    with cond:
                        # resend the last state every 15 s as a keepalive
                        cond.wait_for(lambda: state["seq"] != seq, timeout=15)
                        seq, data = state["seq"], state["data"]
                    self.wfile.write(f"data: {data}\n\n".encode())
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
        elif path in ("/", "/index.html"):
            body = PAGE.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_error(404)


if __name__ == "__main__":
    threading.Thread(target=pump, args=(find_watch(),), daemon=True).start()
    print("Open http://localhost:8765 on the Mac. The game on the watch starts by itself.")
    http.server.ThreadingHTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
