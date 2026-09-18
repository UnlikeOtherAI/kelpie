import { createServer } from "node:http";

const HTML = `<!doctype html>
<html><head><meta charset="utf-8"><title>Kelpie Windows fixture</title>
<style>body { min-height: 2400px; font-family: sans-serif; } #status { margin-top: 32px; }</style>
</head><body>
<h1 id="heading">Kelpie Windows acceptance fixture</h1>
<a id="next-link" href="/next">Next page</a>
<input id="text-input" aria-label="Fixture text" autocomplete="off">
<select id="select-input" aria-label="Fixture select"><option value="first">First</option><option value="second">Second</option></select>
<label><input id="check-input" type="checkbox"> Fixture checkbox</label>
<input id="disabled-input" aria-label="Disabled fixture text" disabled value="cannot change">
<button id="trusted-button">Trusted action</button>
<button id="dialog-button">Dialog</button>
<button id="popup-button">Popup</button>
<pre id="status">ready</pre>
<script>
  window.fixture = { clickTrusted: null, keyTrusted: null, lastKey: null, inputTrusted: null, selectTrusted: null, checkTrusted: null, dialogHandled: false };
  const status = document.querySelector('#status');
  const input = document.querySelector('#text-input');
  document.querySelector('#trusted-button').addEventListener('click', event => {
    window.fixture.clickTrusted = event.isTrusted;
    status.textContent = 'clicked:' + event.isTrusted;
  });
  input.addEventListener('keydown', event => {
    window.fixture.keyTrusted = event.isTrusted;
    window.fixture.lastKey = event.key;
  });
  input.addEventListener('input', event => { window.fixture.inputTrusted = event.isTrusted; });
  document.querySelector('#select-input').addEventListener('change', event => { window.fixture.selectTrusted = event.isTrusted; });
  document.querySelector('#check-input').addEventListener('change', event => { window.fixture.checkTrusted = event.isTrusted; });
  document.querySelector('#dialog-button').addEventListener('click', () => {
    alert('Kelpie acceptance dialog');
    window.fixture.dialogHandled = true;
  });
  document.querySelector('#popup-button').addEventListener('click', () => {
    window.open('/popup', '_blank', 'noopener');
  });
  console.info('kelpie-fixture-console');
  fetch('/api/ping').then(response => response.json()).then(value => { window.fixture.network = value.ok; });
</script>
</body></html>`;

const NEXT_HTML = `<!doctype html><meta charset="utf-8"><title>Kelpie next page</title><h1 id="next-heading">Next page</h1><a id="back-link" href="/">Back</a>`;
const POPUP_HTML = `<!doctype html><meta charset="utf-8"><title>Kelpie popup</title><h1 id="popup-heading">Popup page</h1>`;

function write(response, status, type, body) {
  response.writeHead(status, {
    "cache-control": "no-store",
    "content-type": type,
    "content-length": Buffer.byteLength(body),
  });
  response.end(body);
}

/**
 * Starts an intentionally small, local-only website used by Windows browser
 * release acceptance. It provides fixed DOM, navigation, native-input, dialog,
 * popup, console, and network-observation targets without an external network.
 */
export async function startFixtureServer() {
  const server = createServer((request, response) => {
    const path = new URL(request.url ?? "/", "http://fixture.invalid").pathname;
    if (path === "/") return write(response, 200, "text/html; charset=utf-8", HTML);
    if (path === "/next") return write(response, 200, "text/html; charset=utf-8", NEXT_HTML);
    if (path === "/popup") return write(response, 200, "text/html; charset=utf-8", POPUP_HTML);
    if (path === "/api/ping") return write(response, 200, "application/json", '{"ok":true}');
    if (path === "/slow") {
      setTimeout(() => write(response, 200, "text/html; charset=utf-8", NEXT_HTML), 2_000);
      return;
    }
    return write(response, 404, "text/plain; charset=utf-8", "not found");
  });

  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  if (address === null || typeof address === "string") {
    server.close();
    throw new Error("Fixture server did not expose a TCP port");
  }

  return {
    baseUrl: `http://127.0.0.1:${address.port}`,
    async close() {
      await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    },
  };
}
