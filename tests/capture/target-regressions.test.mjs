// Node 24 can strip the type-only syntax in the shared fixed reader.
// Run after integrating shared workflow source. KELPIE_TARGET_MODULE may point at
// an exact git-show copy in ignored scratch when auditing an earlier revision.
import test from "node:test";
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const source = process.env.KELPIE_TARGET_MODULE
  ? pathToFileURL(process.env.KELPIE_TARGET_MODULE)
  : new URL("../../packages/shared/src/script-target.ts", import.meta.url);
const { resolveScriptTarget } = await import(source.href);

class Element {
  id = "target";
  tagName = "BUTTON";
  isConnected = true;
  parentElement = null;
  children = [];
  rect = { x: 20, y: 30, left: 20, top: 30, right: 120, bottom: 70, width: 100, height: 40 };
  events = [];
  onEvent = () => {};
  getBoundingClientRect() { return this.rect; }
  closest() { return null; }
  matches(selector) { return selector === ":disabled" ? Boolean(this.disabled) : selector === "#" + this.id; }
  getAttribute(name) { return name === "id" ? this.id : null; }
  contains(el) { return el === this || this.children.includes(el); }
  dispatchEvent(event) { this.events.push(event.type); this.onEvent(event); return true; }
}
class Input extends Element {
  tagName = "INPUT";
  type = "text";
  readOnly = false;
  disabled = false;
  stored = "";
  onFocus = () => {};
  focus() { this.onFocus(); }
  get value() { return this.stored; }
  set value(value) { this.stored = value; }
}
function fixture(element = new Element()) {
  let hit = element;
  Object.assign(globalThis, {
    window: {}, document: {
      documentElement: element,
      querySelectorAll: selector => [element, ...element.children].filter(el => el.matches(selector)),
      elementFromPoint: () => hit,
      createTreeWalker(root, whatToShow) {
        const nodes = whatToShow === 1 ? [root, ...root.children] : [];
        let index = 0;
        return { currentNode: root, nextNode: () => nodes[++index] ?? null };
      },
    },
    location: { href: "https://fixture.test/" }, innerWidth: 800, innerHeight: 600,
    getComputedStyle: () => ({ display: "block", visibility: "visible", opacity: "1", overflow: "visible", overflowX: "visible", overflowY: "visible" }),
    HTMLInputElement: Input, HTMLTextAreaElement: class extends Element {},
    HTMLButtonElement: class extends Element {}, HTMLSelectElement: class extends Element {},
    PointerEvent: Event, MouseEvent: Event, InputEvent: Event,
  });
  return { element, setHit(value) { hit = value; } };
}

test("semantic target resolves the center of its visible viewport portion", () => {
  const f = fixture();
  f.element.rect = { x: -80, y: 30, left: -80, top: 30, right: 20, bottom: 70, width: 100, height: 40 };
  const result = resolveScriptTarget({ selector: "#target" }, "acceptance");
  assert.equal(result.ok, true);
  assert.equal(result.x, 10);
  assert.equal(result.y, 50);
  assert.deepEqual(result.visualViewport, { offsetLeft: 0, offsetTop: 0, width: 800, height: 600, scale: 1 });
});

test("dispatch stops uncertain after captured descendant is replaced", () => {
  const f = fixture();
  const oldHit = new Element();
  const newHit = new Element();
  oldHit.id = "old-child"; newHit.id = "new-child";
  oldHit.parentElement = f.element; newHit.parentElement = f.element;
  f.element.children = [oldHit];
  f.setHit(oldHit);
  oldHit.onEvent = event => {
    if (event.type !== "pointerdown") return;
    oldHit.isConnected = false;
    f.element.children = [newHit];
    f.setHit(newHit);
  };
  const first = resolveScriptTarget({ selector: "#target" }, "acceptance");
  const result = resolveScriptTarget({ selector: "#target" }, "acceptance", first.token, true);
  assert.equal(result.ok, false);
  assert.equal(result.mayHaveCompleted, true);
  assert.deepEqual(oldHit.events, ["pointerdown"]);
});

test("focus URL change prevents value mutation and reports uncertainty", () => {
  const f = fixture(new Input());
  f.element.onFocus = () => { globalThis.location.href = "https://fixture.test/next"; };
  const first = resolveScriptTarget({ selector: "#target" }, "acceptance");
  const result = resolveScriptTarget({ selector: "#target" }, "acceptance", first.token, false, { action: "fill", text: "must-not-write" });
  assert.equal(result.ok, false);
  assert.equal(result.mayHaveCompleted, true);
  assert.equal(f.element.value, "");
});

test("focus changing input to readonly prevents value mutation", () => {
  const f = fixture(new Input());
  f.element.onFocus = () => { f.element.readOnly = true; };
  const first = resolveScriptTarget({ selector: "#target" }, "acceptance");
  const result = resolveScriptTarget({ selector: "#target" }, "acceptance", first.token, false, { action: "fill", text: "must-not-write" });
  assert.equal(result.ok, false);
  assert.equal(result.mayHaveCompleted, true);
  assert.equal(f.element.value, "");
});

test("a prior document token cannot alias a newly resolved object", () => {
  fixture();
  const old = resolveScriptTarget({ selector: "#target" }, "acceptance");
  const second = fixture();
  const current = resolveScriptTarget({ selector: "#target" }, "acceptance");
  assert.notEqual(current.token, old.token);
  const result = resolveScriptTarget({ selector: "#target" }, "acceptance", old.token, true);
  assert.equal(result.ok, false);
  assert.equal(result.mayHaveCompleted, false);
  assert.deepEqual(second.element.events, []);
});

test("focus changing input type prevents value mutation", () => {
  const f = fixture(new Input());
  f.element.onFocus = () => { f.element.type = "password"; };
  const first = resolveScriptTarget({ selector: "#target" }, "acceptance");
  const result = resolveScriptTarget({ selector: "#target" }, "acceptance", first.token, false, { action: "fill", text: "must-not-write" });
  assert.equal(result.ok, false);
  assert.equal(result.mayHaveCompleted, true);
  assert.equal(f.element.value, "");
});

test("focus viewport resize prevents value mutation", () => {
  const f = fixture(new Input());
  f.element.onFocus = () => { globalThis.innerWidth = 900; };
  const first = resolveScriptTarget({ selector: "#target" }, "acceptance");
  const result = resolveScriptTarget({ selector: "#target" }, "acceptance", first.token, false, { action: "fill", text: "must-not-write" });
  assert.equal(result.ok, false);
  assert.equal(result.mayHaveCompleted, true);
  assert.equal(f.element.value, "");
});

test("visual viewport clips layout CSS center and refuses offscreen coordinates", () => {
  const f = fixture();
  window.visualViewport = { offsetLeft: 100, offsetTop: 0, width: 300, height: 300, scale: 2 };
  f.element.rect = { x: 350, y: 30, width: 200, height: 40 };
  const result = resolveScriptTarget({ selector: "#target" }, "acceptance");
  assert.equal(result.ok, true); assert.equal(result.x, 375); assert.equal(result.width, 50);
  assert.deepEqual(result.visualViewport, { offsetLeft: 100, offsetTop: 0, width: 300, height: 300, scale: 2 });
  assert.equal(result.viewportWidth, 800); assert.equal(result.viewportHeight, 600);
  assert.equal(resolveScriptTarget({ x: 450, y: 50 }, "acceptance").error, "TARGET_OUTSIDE_VIEWPORT");
});

test("all visual viewport fields fence tokens even with unchanged layout dimensions", () => {
  for (const field of ["offsetLeft", "offsetTop", "width", "height", "scale"]) {
    fixture();
    window.visualViewport = { offsetLeft: 0, offsetTop: 0, width: 400, height: 300, scale: 2 };
    const first = resolveScriptTarget({ selector: "#target" }, "acceptance");
    assert.equal(first.ok, true);
    window.visualViewport[field] += 0.01;
    assert.equal(resolveScriptTarget({ selector: "#target" }, "acceptance", first.token).error, "VIEWPORT_CHANGED", field);
  }
});

test("visual clipping composes with ancestor overflow", () => {
  const f = fixture(), parent = new Element();
  parent.rect = { x: 180, y: 0, width: 80, height: 200 };
  f.element.parentElement = parent; f.element.rect = { x: 150, y: 30, width: 200, height: 40 };
  window.visualViewport = { offsetLeft: 100, offsetTop: 0, width: 200, height: 300, scale: 2 };
  globalThis.getComputedStyle = el => ({ display: "block", visibility: "visible", opacity: "1", overflowX: el === parent ? "hidden" : "visible", overflowY: "visible" });
  const result = resolveScriptTarget({ selector: "#target" }, "acceptance");
  assert.equal(result.ok, true); assert.equal(result.x, 220); assert.equal(result.width, 80);
});

test("visual viewport changing during dispatch reports uncertainty", () => {
  const f = fixture();
  window.visualViewport = { offsetLeft: 0, offsetTop: 0, width: 400, height: 300, scale: 2 };
  const first = resolveScriptTarget({ selector: "#target" }, "acceptance");
  f.element.onEvent = () => { window.visualViewport.scale = 3; };
  assert.deepEqual(resolveScriptTarget({ selector: "#target" }, "acceptance", first.token, true),
    { ok: false, error: "INPUT_UNCERTAIN", mayHaveCompleted: true, sensitive: false, sensitivityKnown: true });
});

for (const change of ["autocomplete", "type", "remove"]) {
  test("capture policy retains sensitivity after focus " + change, () => {
    const f = fixture(new Input());
    f.element.onFocus = () => {
      f.element.autocomplete = "current-password";
      if (change === "type") f.element.type = "password";
      if (change === "remove") f.element.isConnected = false;
    };
    const first = resolveScriptTarget({ selector: "#target" }, "acceptance");
    const result = resolveScriptTarget({ selector: "#target" }, "acceptance", first.token,
      false, { action: "fill", text: "PRIVATE_CANARY" }, false, { refuseSensitive: true });
    assert.equal(result.ok, false);
    assert.equal(result.sensitive, true);
    assert.equal(result.mayHaveCompleted, true);
    assert.equal(f.element.value, "");
    assert.deepEqual(f.element.events, []);
    f.element.autocomplete = "";
    f.element.type = "text";
    const recheck = resolveScriptTarget({ selector: "#target" }, "acceptance", first.token);
    assert.equal(recheck.sensitive, true);
  });
}
test("legacy no-capture edit reports focus-inferred sensitivity", () => {
  const f = fixture(new Input());
  f.element.onFocus = () => { f.element.autocomplete = "new-password"; };
  const first = resolveScriptTarget({ selector: "#target" }, "acceptance");
  const result = resolveScriptTarget({ selector: "#target" }, "acceptance", first.token,
    false, { action: "fill", text: "PRIVATE_CANARY" });
  assert.equal(result.ok, true);
  assert.equal(result.sensitive, true);
  assert.equal(f.element.value, "PRIVATE_CANARY");
});
test("failed type change without capture still carries sensitivity", () => {
  const f = fixture(new Input());
  f.element.onFocus = () => { f.element.type = "password"; };
  const first = resolveScriptTarget({ selector: "#target" }, "acceptance");
  const result = resolveScriptTarget({ selector: "#target" }, "acceptance", first.token,
    false, { action: "type", text: "PRIVATE_CANARY" });
  assert.equal(result.ok, false);
  assert.equal(result.sensitive, true);
  assert.equal(f.element.value, "");
});

test("known false requires the original classified target entry", () => {
  const f = fixture(new Input());
  const first = resolveScriptTarget({ selector: "#target" }, "acceptance");
  assert.equal(first.sensitive, false);
  assert.equal(first.sensitivityKnown, true);
  const missing = resolveScriptTarget({ selector: "#target" }, "acceptance", "foreign-token");
  assert.equal(missing.sensitive, false);
  assert.equal(missing.sensitivityKnown, false);
  f.element.onFocus = () => { f.element.type = "password"; f.element.isConnected = false; };
  const failed = resolveScriptTarget({ selector: "#target" }, "acceptance", first.token,
    false, { action: "fill", text: "PRIVATE_CANARY" });
  assert.equal(failed.sensitive, true);
  assert.equal(failed.sensitivityKnown, true);
  fixture(new Input());
  const newRealm = resolveScriptTarget({ selector: "#target" }, "acceptance", first.token);
  assert.equal(newRealm.sensitive, false);
  assert.equal(newRealm.sensitivityKnown, false);
});
