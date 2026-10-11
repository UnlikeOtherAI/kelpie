#!/usr/bin/env python3
"""Real Android JNI/HTTP/MCP/agent journey. Run against an installed isolated emulator.

No autopair: the harness taps the existing Yes, once approval UI. Bearers remain in
memory. The supplied adb must target only this test emulator (use ANDROID_SERIAL).
"""
import argparse
import json
import os
import re
import subprocess
import threading
import time
import urllib.error
import urllib.request
import uuid
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

FIXTURE = b'''<!doctype html><meta name="viewport" content="width=device-width"><title>Gateway fixture</title>
<label>Query<input id="query" aria-label="Query" value="seed"></label>
<button id="count" onclick="window.activationCount=(window.activationCount||0)+1;document.title='Count:'+window.activationCount">Count</button>
<button id="slow" onclick="window.slowActivations=(window.slowActivations||0)+1;let end=Date.now()+35000;while(Date.now()<end){};document.title='Slow:'+window.slowActivations">Slow</button>
<script>setInterval(async()=>{let cmd=await(await fetch('/command')).json();
if(cmd.replace){let el=document.querySelector('#count');el.replaceWith(el.cloneNode(true));document.title='Replaced'}
if(cmd.spoof){let el=document.createElement('button');el.textContent='Spoof';el.setAttribute('data-sn-ref',cmd.spoof);
el.onclick=()=>document.title='WRONG';document.body.append(el);document.title='Spoof ready'}},100)</script>'''


class FixtureHandler(BaseHTTPRequestHandler):
    command = {}
    calls = []
    model_mode = 'read'
    model_stage = 0
    model_catalog_chars = None
    tab = None

    def log_message(self, *_):
        pass

    def send_json(self, value):
        data = json.dumps(value).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == '/command':
            command, FixtureHandler.command = FixtureHandler.command, {}
            return self.send_json(command)
        if self.path == '/v1/models':
            return self.send_json({'object': 'list', 'data': [{'id': 'gateway-fixture'}]})
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.send_header('Content-Length', str(len(FIXTURE)))
        self.end_headers()
        self.wfile.write(FIXTURE)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        names = [tool['function']['name'] for tool in body.get('tools', [])]
        expected = ['update_task_list', 'kelpie_browser_control', 'kelpie_extensions', 'kelpie_extension_tools', 'kelpie_extension']
        assert names == expected, 'Agent did not offer the shared compact catalog'
        FixtureHandler.model_catalog_chars = len(json.dumps(body['tools'], separators=(',', ':')))
        FixtureHandler.calls.append(names)
        stage = FixtureHandler.model_stage
        FixtureHandler.model_stage += 1
        name = 'kelpie_browser_control'
        args = {'request': {'version': 1, 'method': 'tab.snapshot', 'tabId': self.tab, 'params': {}}}
        if self.model_mode == 'read':
            if stage == 0:
                args['request']['method'] = 'capabilities'
                del args['request']['tabId']
            elif stage == 1:
                observed = json.loads(body['messages'][-1]['content'])['result']['value']['methods']
                assert not set(observed) & {'tab.click', 'tab.type', 'tab.goto', 'tab.screenshot', 'tabs.new', 'tabs.close'}
                name, args = 'kelpie_extensions', {}
            elif stage == 2:
                extensions = json.loads(body['messages'][-1]['content'])['result']['value']
                assert 'kelpie_get_page_text' in extensions and 'kelpie_fill' not in extensions
                name, args = 'kelpie_extension', {'name': 'kelpie_get_page_text', 'arguments': {}}
            else:
                return self.answer()
        elif self.model_mode == 'timeout':
            if stage == 1:
                observed = json.loads(body['messages'][-1]['content'])['result']['value']
                ref = next(el['ref'] for el in observed['elements'] if el['name'] == 'Slow')
                args['request'].update(method='tab.click', params={'ref': ref})
            elif stage > 1:
                raise AssertionError('AI run replayed or continued after an uncertain action')
        else:
            if stage == 1:
                observed = json.loads(body['messages'][-1]['content'])['result']['value']
                ref = next(el['ref'] for el in observed['elements'] if el['name'] == 'Query')
                args['request'].update(method='tab.type', params={'ref': ref, 'text': '_AI'})
            elif stage == 3:
                observed = json.loads(body['messages'][-1]['content'])['result']['value']
                ref = next(el['ref'] for el in observed['elements'] if el['name'] == 'Count')
                args['request'].update(method='tab.click', params={'ref': ref})
            elif stage >= 5:
                return self.answer()
        function = {'name': name, 'arguments': json.dumps(args)}
        self.send_json({'choices': [{'message': {'role': 'assistant', 'content': None,
            'tool_calls': [{'id': 'call-' + str(stage), 'type': 'function', 'function': function}]}, 'finish_reason': 'tool_calls'}]})

    def answer(self):
        self.send_json({'choices': [{'message': {'role': 'assistant', 'content': 'Verified fixture'}, 'finish_reason': 'stop'}]})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', default='http://127.0.0.1:18420')
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--fixture-port', type=int, default=18421)
    args = parser.parse_args()
    server = ThreadingHTTPServer(('0.0.0.0', args.fixture_port), FixtureHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    token = None

    def request(path, value=None, authenticated=True, extra_headers=None):
        data = None if value is None else json.dumps(value).encode()
        headers = {'Content-Type': 'application/json'}
        if authenticated and token:
            headers['Authorization'] = 'Bearer ' + token
        headers.update(extra_headers or {})
        req = urllib.request.Request(args.base + path, data, headers)
        try:
            with urllib.request.urlopen(req, timeout=45) as response:
                body = response.read()
                return response.status, json.loads(body) if body else None
        except urllib.error.HTTPError as error:
            body = error.read()
            return error.code, json.loads(body) if body else None

    def native(method, params=None):
        status, result = request('/v1/' + method, params or {})
        assert status == 200 and result.get('success'), 'Native fixture operation failed: ' + method
        return result

    def core(method, tab=None, params=None, succeeds=True):
        value = {'version': 1, 'method': method, 'params': params or {}}
        if tab:
            value['tabId'] = tab
        status, result = request('/v1/browser-control', value)
        assert status == 200 and result['ok'] == succeeds, 'Canonical operation failed: ' + method
        return result.get('value') if succeeds else result['error']

    def rpc(name, arguments=None):
        status, result = request('/mcp', {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call',
            'params': {'name': name, 'arguments': arguments or {}}})
        assert status == 200 and 'result' in result, 'MCP protocol result missing'
        return json.loads(next(item['text'] for item in result['result']['content'] if item['type'] == 'text'))

    def wait_title(tab_id, expected):
        for _ in range(40):
            if core('tab.title', tab_id) == expected:
                return
            time.sleep(0.25)
        raise AssertionError('Fixture command did not settle')

    for path in ('/v1/browser-control', '/mcp'):
        assert request(path, {'version': 1, 'method': 'capabilities'}, False)[0] == 401
    print('PASS unauthenticated HTTP/MCP denial', flush=True)
    status, pending = request('/v1/pair', {'clientId': str(uuid.uuid4()), 'clientName': 'Gateway emulator verification'}, False)
    assert status == 202
    for _ in range(15):
        subprocess.run([args.adb, 'shell', 'uiautomator', 'dump', '/sdcard/gateway-ui.xml'], check=True, stdout=subprocess.DEVNULL)
        xml = subprocess.check_output([args.adb, 'shell', 'cat', '/sdcard/gateway-ui.xml'])
        button = next((node for node in ET.fromstring(xml).iter('node') if node.get('text') == 'Yes, once'), None)
        if button is not None:
            x1, y1, x2, y2 = map(int, re.findall(r'\d+', button.get('bounds')))
            subprocess.run([args.adb, 'shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2)], check=True)
            break
        time.sleep(1)
    else:
        raise AssertionError('Existing pairing approval UI unavailable')
    _, approved = request('/v1/pair/status?requestId=' + pending['requestId'], authenticated=False)
    assert approved['status'] == 'approved'
    token = approved['token']
    print('PASS existing session approval and bearer', flush=True)
    assert request('/mcp')[0] == 405
    assert request('/mcp', {}, extra_headers={'MCP-Protocol-Version': 'unsupported'})[0] == 400
    assert request('/mcp', {}, extra_headers={'Origin': 'null'})[0] == 403
    assert request('/mcp', {'jsonrpc': '2.0', 'method': 'notifications/initialized'}) == (202, None)
    print('PASS MCP transport notification/version/Origin/GET boundaries', flush=True)
    fixture_url = f'http://10.0.2.2:{args.fixture_port}/fixture'
    tab = core('tabs.new', params={'url': fixture_url})['id']
    core('tab.goto', tab, {'url': fixture_url})
    subprocess.run([os.environ.get('NODE', 'node'), str(Path(__file__).with_name('android-browser-gateway-mcp.mjs'))],
        input=json.dumps({'base': args.base, 'token': token, 'tab': tab}).encode(), check=True)
    assert 'page.press' not in core('capabilities')['methods']
    first = core('tab.snapshot', tab)
    assert 'seed' not in json.dumps(first)
    query = next(el['ref'] for el in first['elements'] if el['name'] == 'Query')
    core('tab.type', tab, {'ref': query, 'text': '_tail'})
    assert native('evaluate', {'expression': 'document.querySelector("#query").value'})['result'] == 'seed_tail'
    assert core('tab.type', tab, {'ref': query, 'text': '_again'}, False)['code'] == 'STALE_REFERENCE'
    second = core('tab.snapshot', tab)
    count = next(el['ref'] for el in second['elements'] if el['name'] == 'Count')
    FixtureHandler.command = {'replace': True}
    wait_title(tab, 'Replaced')
    assert core('tab.click', tab, {'ref': count}, False)['code'] == 'STALE_REFERENCE'
    third = core('tab.snapshot', tab)
    count = next(el['ref'] for el in third['elements'] if el['name'] == 'Count')
    FixtureHandler.command = {'spoof': count}
    wait_title(tab, 'Spoof ready')
    core('tab.click', tab, {'ref': count})
    assert core('tab.title', tab) == 'Count:1'
    print('PASS JNI snapshot/value omission/append/stale/replacement/spoof guards', flush=True)
    other = core('tabs.new', params={'url': fixture_url})['id']
    core('tabs.select', tab)
    cross = core('tab.snapshot', tab)
    cross_ref = next(el['ref'] for el in cross['elements'] if el['name'] == 'Count')
    assert core('tab.click', other, {'ref': cross_ref}, False)['code'] == 'STALE_REFERENCE'
    observe = core('tab.snapshot', tab)
    old = next(el['ref'] for el in observe['elements'] if el['name'] == 'Query')
    core('tab.snapshot', tab)
    assert core('tab.type', tab, {'ref': old, 'text': 'x'}, False)['code'] == 'STALE_REFERENCE'
    latest = core('tab.snapshot', tab)
    old = next(el['ref'] for el in latest['elements'] if el['name'] == 'Query')
    native('fill', {'selector': '#query', 'value': 'legacy'})
    assert core('tab.type', tab, {'ref': old, 'text': 'x'}, False)['code'] == 'STALE_REFERENCE'
    assert rpc('kelpie_extensions')['ok']
    extensions = rpc('kelpie_extension_tools', {'names': ['kelpie_get_page_text']})['value']
    assert extensions[0]['inputSchema']['type'] == 'object'
    assert rpc('kelpie_extension', {'name': 'kelpie_get_page_text', 'arguments': {}})['ok']
    screenshot = request('/mcp', {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call',
        'params': {'name': 'kelpie_browser_control', 'arguments': {'request': {'version': 1, 'method': 'tab.screenshot', 'tabId': tab}}}})[1]
    assert screenshot['result']['content'][0]['type'] == 'image'
    print('PASS cross-tab/latest-snapshot/legacy invalidation and MCP extensions/image', flush=True)
    slow = core('tab.snapshot', tab)
    slow_ref = next(el['ref'] for el in slow['elements'] if el['name'] == 'Slow')
    uncertain = core('tab.click', tab, {'ref': slow_ref}, False)
    assert uncertain['code'] == 'CANCELLED' and uncertain['mayHaveCompleted']
    retirement_started = time.monotonic()
    wait_title(tab, 'Slow:1')
    assert time.monotonic() - retirement_started >= 3
    print('PASS actual renderer timeout/retirement/reconciliation/one activation', flush=True)
    endpoint = native('ai-endpoint-save', {'name': 'Gateway fixture', 'baseURL': f'http://10.0.2.2:{args.fixture_port}/v1',
        'model': 'gateway-fixture', 'capabilities': {'toolCalling': True}})['endpoint']['id']
    native('ai-load', {'backend': 'openai', 'endpoint': endpoint})
    FixtureHandler.tab = tab
    for mode in ('read', 'write', 'timeout'):
        core('tab.goto', tab, {'url': fixture_url})
        FixtureHandler.model_mode, FixtureHandler.model_stage = mode, 0
        infer = {'prompt': 'Verify gateway fixture', 'agent': True, 'allowActions': mode != 'read', 'tabId': tab, 'maxSteps': 10}
        if mode == 'timeout':
            status, stopped = request('/v1/ai-infer', infer)
            assert status == 400 and stopped['error']['code'] == 'ACTION_UNCERTAIN'
            assert stopped['error']['diagnostics']['error']['mayHaveCompleted']
            assert FixtureHandler.model_stage == 2
            wait_title(tab, 'Slow:1')
        else:
            native('ai-infer', infer)
        if mode == 'write':
            assert native('evaluate', {'expression': 'document.querySelector("#query").value'})['result'] == 'seed_AI'
            assert core('tab.title', tab) == 'Count:1'
    native('ai-endpoint-remove', {'id': endpoint})
    print('PASS built-in agent compact catalog/read-only admission/observed-ref actions/uncertainty stop', flush=True)
    print('Actual last agent catalog characters:', FixtureHandler.model_catalog_chars, flush=True)
    core('tabs.close', other)
    server.shutdown()
    print('Android emulator gateway journey passed; physical device unverified', flush=True)


if __name__ == '__main__':
    main()
