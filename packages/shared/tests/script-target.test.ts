import { afterEach, describe, expect, it, vi } from "vitest";
import { resolveScriptTarget } from "../src/script-target.js";

class ElementStub {
  isConnected = true;
  parentElement = null;
  rect = { x: 20, y: 30, width: 100, height: 40 };
  events: string[] = [];
  onEvent?: () => void;
  getBoundingClientRect() { return this.rect; }
  closest() { return null; }
  matches() { return false; }
  contains(el: unknown) { return el === this; }
  dispatchEvent(event: Event) { this.events.push(event.type); this.onEvent?.(); return true; }
}
function fixture(count = 1) {
  const element = new ElementStub();
  let hit: ElementStub | null = element;
  const doc = { querySelectorAll: () => Array.from({ length: count }, () => element), elementFromPoint: () => hit };
  vi.stubGlobal("window", {});
  vi.stubGlobal("document", doc);
  vi.stubGlobal("location", { href: "http://fixture/" });
  vi.stubGlobal("innerWidth", 800);
  vi.stubGlobal("innerHeight", 600);
  vi.stubGlobal("getComputedStyle", () => ({ display: "block", visibility: "visible", opacity: "1" }));
  for (const name of ["HTMLButtonElement", "HTMLInputElement", "HTMLTextAreaElement", "HTMLSelectElement"]) vi.stubGlobal(name, class { readonly kind = "non-control"; });
  vi.stubGlobal("PointerEvent", Event);
  vi.stubGlobal("MouseEvent", Event);
  return { element, obscure: () => { hit = new ElementStub(); } };
}
afterEach(() => vi.unstubAllGlobals());
describe("script target identity fencing", () => {
  it("resolves the center and refuses moved, obscured, detached and wrong-document targets before input", () => {
    const f = fixture();
    const target = { selector: "#submit" };
    const first = resolveScriptTarget(target, "private");
    expect(first).toMatchObject({ ok: true, x: 70, y: 50, viewportWidth: 800, viewportHeight: 600 });
    f.element.rect.x += 1;
    expect(resolveScriptTarget(target, "private", first.token, true)).toMatchObject({ error: "TARGET_MOVED", mayHaveCompleted: false });
    f.element.rect.x -= 1;
    f.obscure();
    expect(resolveScriptTarget(target, "private", first.token, true).error).toBe("TARGET_OBSCURED");
    f.element.isConnected = false;
    expect(resolveScriptTarget(target, "private", first.token, true).error).toBe("STALE_TARGET");
    expect(f.element.events).toEqual([]);
  });
  it("refuses ambiguity and viewport changes instead of retargeting", () => {
    fixture(2);
    expect(resolveScriptTarget({ selector: "button" }, "private").error).toBe("AMBIGUOUS_TARGET");
    fixture();
    const first = resolveScriptTarget({ selector: "button" }, "private");
    vi.stubGlobal("innerWidth", 900);
    expect(resolveScriptTarget({ selector: "button" }, "private", first.token, true).error).toBe("VIEWPORT_CHANGED");
  });
  it("dispatches coordinates and stops uncertain event sequences after page mutation", () => {
    const f = fixture();
    const target = { selector: "button" };
    const first = resolveScriptTarget(target, "private");
    f.element.onEvent = () => { f.element.isConnected = false; };
    expect(resolveScriptTarget(target, "private", first.token, true)).toMatchObject({ error: "INPUT_UNCERTAIN", mayHaveCompleted: true });
    expect(f.element.events).toEqual(["pointerdown"]);
  });
});
