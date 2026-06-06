#!/usr/bin/env python3
"""Tiny local server for the carl roadmap.

Serves the roadmap page and persists edits straight to roadmap.json — no
downloads, no file pickers. Standard library only; no installs.

Run from anywhere:
    python3 roadmap/server.py
then open http://localhost:8770/  (use --port to change).

Endpoints:
    GET  /api/roadmap  -> current roadmap.json
    POST /api/roadmap  -> overwrite roadmap.json with the posted JSON (atomic)
Everything else is served as a static file from this folder.
"""

import argparse
import json
import os
import tempfile
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
DATA_FILE = os.path.join(HERE, "roadmap.json")


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        # Serve files relative to the roadmap/ folder regardless of cwd.
        super().__init__(*args, directory=HERE, **kwargs)

    def _send_json(self, obj, status=200):
        body = json.dumps(obj, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.split("?")[0] == "/api/roadmap":
            try:
                with open(DATA_FILE, "r", encoding="utf-8") as f:
                    self._send_json(json.load(f))
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
            return
        super().do_GET()

    def do_POST(self):
        if self.path.split("?")[0] != "/api/roadmap":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            payload = self.rfile.read(length)
            data = json.loads(payload)  # validate it parses before writing
            # Atomic write: temp file in the same dir, then replace.
            fd, tmp = tempfile.mkstemp(dir=HERE, suffix=".tmp")
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
                f.write("\n")
            os.replace(tmp, DATA_FILE)
            self._send_json({"ok": True})
        except json.JSONDecodeError as e:
            self._send_json({"error": "invalid JSON: " + str(e)}, 400)
        except Exception as e:
            self._send_json({"error": str(e)}, 500)

    def log_message(self, fmt, *args):
        pass  # quiet


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8770)
    args = ap.parse_args()
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = f"http://localhost:{args.port}/"
    print(f"carl roadmap → {url}  (editing saves to {os.path.relpath(DATA_FILE)})")
    print("Ctrl+C to stop.")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped.")


if __name__ == "__main__":
    main()
