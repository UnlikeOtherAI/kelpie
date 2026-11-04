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
