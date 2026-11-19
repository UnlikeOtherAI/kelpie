#!/usr/bin/env python3
"""Exercise the tab API against an isolated KelpieEmbeddingHost control port."""

import argparse
import http.server
import json
import threading
import time
import urllib.error
import urllib.request


class FixturePage(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        title = {"first": "Issue 73 first", "second": "Issue 73 second"}.get(self.path[1:])
        if title is None:
            self.send_error(404)
            return
        page = f"<!doctype html><title>{title}</title><body style='height:3200px'><h1>{title}</h1></body>".encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(page)))
        self.end_headers()
        self.wfile.write(page)


def wait_for(label, check):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(0.05)
    raise AssertionError(f"Timed out waiting for {label}")


def verify(control_port, page_port):
    def exchange(path, body):
        target = f"http://127.0.0.1:{control_port}{path}"
        request = urllib.request.Request(
            target, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"}
        )
        try:
            response = urllib.request.urlopen(request, timeout=12)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            return json.load(response)

    def request(method, **body):
        return exchange(f"/v1/{method}", body)

    def call(method, **body):
        result = request(method, **body)
        assert result.get("success") is True, (method, result)
        return result

    def expect_error(code, method, **body):
        result = request(method, **body)
        assert result.get("error", {}).get("code") == code, (method, result)

    def open_page(path):
        tab_id = call("new-tab", url=f"http://127.0.0.1:{page_port}/{path}")["tabId"]
        wait_for(f"{path} document", lambda: any(
            tab["id"] == tab_id and tab["title"] == f"Issue 73 {path}" and not tab["isLoading"]
            for tab in call("get-tabs")["tabs"]
        ))
        return tab_id

    def select(tab_id):
        assert call("switch-tab", tabId=tab_id)["tab"]["id"] == tab_id

    def close(tab_id):
        assert call("close-tab", tabId=tab_id)["closed"] == tab_id

    def evaluate(tab_id, expression):
        return call("evaluate", tabId=tab_id, expression=expression)["result"]

    def mcp_tabs():
        response = exchange("/mcp", {
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": {"name": "kelpie_browser_control", "arguments": {
                "request": {"version": 1, "method": "tabs.list"}
            }}
        })
        result = json.loads(response["result"]["content"][0]["text"])
        assert result["ok"], result
        return result["value"]

    call("set-renderer", engine="chromium")
    initial_count = call("get-tabs")["count"]
    first = open_page("first")
    evaluate(first, "window.tabMarker = 'first'; scrollTo(0, 180); document.cookie = 'kelpie_issue73=shared'")
    second = open_page("second")
    evaluate(second, "window.tabMarker = 'second'; scrollTo(0, 360)")
    assert "kelpie_issue73=shared" in evaluate(second, "document.cookie")
    assert {first, second} <= {tab["id"] for tab in mcp_tabs()}

    for _ in range(10):
        select(first)
        select(second)
    assert call("get-tabs")["activeTab"] == second
    assert evaluate(second, "window.tabMarker + ':' + scrollY") == "second:360"
    select(first)
    assert evaluate(first, "window.tabMarker + ':' + scrollY") == "first:180"
    close(second)
    expect_error("TAB_NOT_FOUND", "switch-tab", tabId=second)
    assert evaluate(first, "window.tabMarker") == "first"

    # Each iteration closes a tab whose first load may still be in progress.
    for _ in range(17):
        temporary = call("new-tab", url=f"http://127.0.0.1:{page_port}/second")["tabId"]
        select(first)
        close(temporary)
    assert call("get-tabs")["count"] == initial_count + 1
    assert evaluate(first, "window.tabMarker") == "first"
    expect_error("PARTITION_UNSUPPORTED", "new-tab", partition="issue73-fixture")
    print("Chromium retained DOM and scroll state, shared its default cookies, and passed 51 rapid tab operations.")

    call("set-renderer", engine="webkit")
    webkit_first = open_page("first")
    webkit_second = open_page("second")
    select(webkit_first)
    assert call("get-tabs")["activeTab"] == webkit_first
    close(webkit_second)
    partition = call("new-tab", partition="issue73-fixture", persistent=False)["tabId"]
    expect_error("ENGINE_SWITCH_BLOCKED_BY_PARTITION", "set-renderer", engine="chromium")
    close(partition)
    close(webkit_first)
    call("set-renderer", engine="chromium")
    select(first)
    assert evaluate(first, "window.tabMarker + ':' + scrollY") == "first:180"
    close(first)
    print("WebKit tabs, partition protection, and the renderer round trip passed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("control_port", type=int, help="Loopback port of the isolated embedding fixture")
    args = parser.parse_args()
    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), FixturePage) as page_server:
        threading.Thread(target=page_server.serve_forever, daemon=True).start()
        try:
            verify(args.control_port, page_server.server_port)
        finally:
            page_server.shutdown()


if __name__ == "__main__":
    main()
