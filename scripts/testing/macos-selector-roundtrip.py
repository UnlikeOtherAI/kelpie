#!/usr/bin/env python3
"""Exercise selectors against the native Mac embedding verification host.

Launch a fresh KelpieEmbeddingHost.app with --control-port PORT and
--control-second-window. Run locally, or forward PORT and a fixed fixture
port in opposite directions over SSH to run the client on Windows.
"""

import argparse
import http.server
import itertools
import json
import threading
import time
import urllib.error
import urllib.request
import uuid


class FixturePage(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        page = {
            "/sign-in": '<button onclick="window.hits++">Sign in</button>',
            "/filler": "<p>No button</p>",
            "/duplicate": """
                <section id="panel"><button id="2:entry" onclick="window.decoyHits++">Other action</button></section>
                <section id="panel"><button id="2:entry" onclick="window.hits++">Sign in</button></section>
            """,
            "/duplicate-parent": """
                <section id="panel"><button onclick="window.decoyHits++">Other action</button></section>
                <section id="panel"><button onclick="window.hits++">Sign in</button></section>
            """,
            "/escaped": '<button id="2:entry" onclick="window.hits++">Sign in</button>',
        }.get(self.path)
        if page is None:
            self.send_error(404)
            return
        payload = (
            f"<!doctype html><title>{self.path[1:]}</title>"
            "<body><script>window.hits=0;window.decoyHits=0</script>" + page
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def wait_for(label, condition):
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.05)
    raise AssertionError(f"Timed out waiting for {label}")


def verify(control_port, page_port, engine, transport):
    request_ids = itertools.count(1)

    def exchange(path, body):
        request = urllib.request.Request(
            f"http://127.0.0.1:{control_port}{path}", data=json.dumps(body).encode(),
            headers={
                "Content-Type": "application/json", "Accept": "application/json, text/event-stream",
                "MCP-Protocol-Version": "2025-06-18",
            },
        )
        try:
            response = urllib.request.urlopen(request, timeout=15)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            data = response.read()
            return json.loads(data) if data else None

    def http(method, **body):
        result = exchange(f"/v1/{method}", body)
        assert "error" not in result, (method, body, result)
        return result

    def rpc(method, params):
        response = exchange("/mcp", {
            "jsonrpc": "2.0", "id": next(request_ids), "method": method, "params": params,
        })
        assert "error" not in response, response
        return response["result"]

    def mcp(name, **arguments):
        result = rpc("tools/call", {"name": "kelpie_extension", "arguments": {
            "name": name, "arguments": arguments,
        }})
        return json.loads(result["content"][0]["text"])

    def call(method, **body):
        if transport == "http":
            return http(method, **body)
        result = mcp("kelpie_" + method.replace("-", "_"), **body)
        assert result["ok"], (method, body, result)
        return result["value"]

    def expect_refusal(method, code, **body):
        raw = exchange(f"/v1/{method}", body)
        assert raw.get("error", {}).get("code") == code, (method, raw)
        if transport == "mcp":
            result = mcp("kelpie_" + method.replace("-", "_"), **body)
            assert result["error"]["code"] == "COMMAND_FAILED", (method, result)

    def window_tabs(window_id):
        return http("get-tabs", windowId=window_id)

    def open_page(window_id, page):
        tab_id = http("new-tab", windowId=window_id, url=f"http://127.0.0.1:{page_port}/{page}")["tabId"]
        wait_for(f"{page} in {tab_id}", lambda: any(
            tab["id"] == tab_id and tab["title"] == page and not tab["isLoading"]
            for tab in window_tabs(window_id)["tabs"]
        ))
        return tab_id

    def hits(tab_id):
        return evaluate(tab_id, "[window.hits, window.decoyHits]")

    def evaluate(tab_id, expression):
        return call("evaluate", tabId=tab_id, expression=expression)["result"]

    def select(tab_id):
        assert http("switch-tab", tabId=tab_id)["tab"]["id"] == tab_id

    def round_trip(tab_id, expected_hits):
        found = call("find-element", text="Sign in", tabId=tab_id)
        assert found["found"] and found["element"]["tag"] == "button", found
        selector = found["element"]["selector"]
        assert isinstance(selector, str) and selector, found
        clicked = call("click", selector=selector, tabId=tab_id)
        assert clicked["success"], clicked
        observed = hits(tab_id)
        assert observed == expected_hits, (tab_id, selector, observed, expected_hits)
        return selector

    wait_for("two fixture windows", lambda: len(http("get-tabs").get("windows", [])) == 2)
    first, second = http("get-tabs")["windows"]
    assert first["count"] == second["count"] == 1, (first, second)
    http("set-renderer", engine=engine)
    if transport == "mcp":
        hello = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                   "clientInfo": {"name": "kelpie-selector-fixture", "version": "1"}})
        assert hello["protocolVersion"] == "2025-06-18", hello
        assert exchange("/mcp", {"jsonrpc": "2.0", "method": "notifications/initialized"}) is None
    first_id, second_id = first["windowId"], second["windowId"]
    target = open_page(first_id, "sign-in")
    other_window = open_page(second_id, "sign-in")
    http("close-tab", tabId=first["activeTab"])
    http("close-tab", tabId=second["activeTab"])
    decoy = open_page(first_id, "sign-in")
    for _ in range(10):
        http("new-tab", windowId=first_id, url=f"http://127.0.0.1:{page_port}/filler")
    assert window_tabs(first_id)["count"] == 12

    select(target)
    selector = round_trip(target, [1, 0])
    assert selector == "button:nth-of-type(1)", selector
    select(decoy)
    assert window_tabs(first_id)["activeTab"] == decoy
    if engine == "webkit":
        assert round_trip(target, [2, 0]) == selector
    else:
        expect_refusal("find-element", "RENDERER_HIDDEN", text="Sign in", tabId=target)
        expect_refusal("click", "RENDERER_HIDDEN", selector=selector, tabId=target)
    assert window_tabs(first_id)["activeTab"] == decoy
    assert round_trip(other_window, [1, 0]) == selector
    assert hits(decoy) == [0, 0]
    if engine == "chromium":
        select(target)
        assert hits(target) == [1, 0]
        assert round_trip(target, [2, 0]) == selector
    assert hits(target) == [2, 0]
    background = "activated background target" if engine == "webkit" else "refused hidden target, then recovered"
    print(f"{engine}/{transport}: 12 tabs, {background}, and second window passed; identical decoy untouched", flush=True)

    expect_refusal("click", "TAB_NOT_FOUND", selector=selector, tabId=str(uuid.uuid4()))
    select(decoy)
    assert hits(decoy) == [0, 0]
    assert hits(other_window) == [1, 0]

    escaped_tab = open_page(first_id, "escaped")
    escaped = round_trip(escaped_tab, [1, 0])
    assert escaped.startswith("#") and "\\" in escaped, escaped
    duplicate_tab = open_page(first_id, "duplicate")
    assert evaluate(duplicate_tab, """document.querySelectorAll('[id="2:entry"]').length""") == 2
    unique = round_trip(duplicate_tab, [1, 0])
    missing = call("find-element", text="Absent in the document", tabId=duplicate_tab)
    assert missing["found"] is False, missing
    duplicate_parent = round_trip(open_page(first_id, "duplicate-parent"), [1, 0])
    print(f"{engine}/{transport}: escaped id {escaped!r}, duplicate id {unique!r}, "
          f"duplicate parent {duplicate_parent!r}, and missing element passed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("control_port", type=int, help="Loopback port of the isolated embedding fixture")
    parser.add_argument("--fixture-port", type=int, default=0, help="Fixed fixture port for SSH reverse forwarding")
    parser.add_argument("--engine", choices=("webkit", "chromium"), default="webkit")
    parser.add_argument("--transport", choices=("http", "mcp"), default="mcp")
    args = parser.parse_args()
    with http.server.ThreadingHTTPServer(("127.0.0.1", args.fixture_port), FixturePage) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            verify(args.control_port, server.server_port, args.engine, args.transport)
        finally:
            server.shutdown()


if __name__ == "__main__":
    main()
