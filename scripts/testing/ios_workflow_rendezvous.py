"""A loopback test fixture exchanges one public tab UUID and a completion state with XCTest."""
import json
import threading
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer


class HostedCLIRendezvous:
    def __init__(self, nonce):
        self.tab = None
        self.outcome = "pending"
        self.lock = threading.Lock()
        owner = self

        class Request(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def reply(self, status, value):
                body = json.dumps(value).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(body)

            def do_GET(self):
                if self.path != "/" + nonce:
                    return self.reply(404, {})
                with owner.lock:
                    value = owner.outcome
                self.reply(200, {"state": value})

            def do_POST(self):
                if self.path != "/" + nonce:
                    return self.reply(404, {})
                try:
                    count = int(self.headers.get("Content-Length", 0))
                    if not 1 <= count <= 128:
                        return self.reply(400, {})
                    value = json.loads(self.rfile.read(count))
                    if set(value) != {"tabId"}:
                        return self.reply(400, {})
                    tab = str(uuid.UUID(value["tabId"])).upper()
                except (TypeError, ValueError, AttributeError):
                    return self.reply(400, {})
                with owner.lock:
                    if owner.tab is not None:
                        return self.reply(409, {})
                    owner.tab = tab
                self.reply(202, {"accepted": True})

        self.server = HTTPServer(("127.0.0.1", 0), Request)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def start(self):
        self.thread.start()

    def current_tab(self):
        with self.lock:
            return self.tab

    def finish(self, succeeded):
        with self.lock:
            self.outcome = "passed" if succeeded else "failed"

    def close(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(2)
