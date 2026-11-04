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
  matches(selector: string) { return selector !== ":disabled"; }
  contains(el: unknown) { return el === this; }
  dispatchEvent(event: Event) { this.events.push(event.type); this.onEvent?.(); return true; }
}
function fixture(count = 1, element = new ElementStub()) {
  let hit: ElementStub | null = element;
  const doc = { documentElement: element, createTreeWalker: (_root: unknown, mask: number) => {
    let index = 0;
    return { currentNode: element, nextNode: () => mask !== 1 || ++index >= count ? null : element };
  }, elementFromPoint: () => hit };
  vi.stubGlobal("window", {});
  vi.stubGlobal("document", doc);
  vi.stubGlobal("location", { href: "http://fixture/" });
  vi.stubGlobal("innerWidth", 800);
  vi.stubGlobal("innerHeight", 600);
  vi.stubGlobal("getComputedStyle", () => ({ display: "block", visibility: "visible", opacity: "1", overflowX: "visible", overflowY: "visible" }));
  for (const name of ["HTMLButtonElement", "HTMLInputElement", "HTMLTextAreaElement", "HTMLSelectElement"]) vi.stubGlobal(name, class { readonly kind = "non-control"; });
  vi.stubGlobal("PointerEvent", Event);
  vi.stubGlobal("MouseEvent", Event);
  return { element, setHit: (next: ElementStub) => { hit = next; }, obscure: () => { hit = new ElementStub(); } };
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

describe("target safety regressions", () => {
  it("uses the center of the viewport-clipped visible rectangle", () => {
    const f = fixture();
    f.element.rect = { x: -80, y: 30, width: 100, height: 40 };
    expect(resolveScriptTarget({ selector: "button" }, "private")).toMatchObject({ ok: true, x: 10, y: 50, width: 20 });
  });
  it("stops after the exact hit descendant is replaced", () => {
    class Button extends ElementStub {
      child = new ElementStub();
      contains(el: unknown) { return el === this || el === this.child; }
    }
    const button = new Button();
    const f = fixture(1, button);
    const oldHit = button.child;
    f.setHit(oldHit);
    const first = resolveScriptTarget({ selector: "button" }, "private");
    oldHit.onEvent = () => { oldHit.isConnected = false; button.child = new ElementStub(); f.setHit(button.child); };
    expect(resolveScriptTarget({ selector: "button" }, "private", first.token, true)).toMatchObject({ error: "INPUT_UNCERTAIN", mayHaveCompleted: true });
    expect(oldHit.events).toEqual(["pointerdown"]);
  });
  it.each(["url", "readonly", "viewport", "size", "type"])("rechecks %s after focus before editing", mutation => {
    class Input extends ElementStub {
      readOnly = false;
      disabled = false;
      type = "text";
      autocomplete = "";
      private stored = "before";
      get value() { return this.stored; }
      set value(value: string) { this.stored = value; }
      focus() {
        if (mutation === "url") vi.stubGlobal("location", { href: "http://changed/" });
        if (mutation === "readonly") this.readOnly = true;
        if (mutation === "viewport") vi.stubGlobal("innerWidth", 900);
        if (mutation === "size") this.rect.width += 5;
        if (mutation === "type") this.type = "password";
      }
    }
    const input = new Input();
    fixture(1, input);
    vi.stubGlobal("HTMLInputElement", Input);
    const first = resolveScriptTarget({ selector: "input" }, "private");
    expect(resolveScriptTarget({ selector: "input" }, "private", first.token, false, { action: "fill", text: "after" })).toMatchObject({ error: "INPUT_UNCERTAIN", mayHaveCompleted: true });
    expect(input.value).toBe("before");
  });
  it("namespaces tokens across document replacement and fresh resolution", () => {
    const f = fixture();
    const old = resolveScriptTarget({ selector: "button" }, "private");
    vi.stubGlobal("document", { documentElement: f.element, createTreeWalker: () => ({ currentNode: f.element, nextNode: () => null }), elementFromPoint: () => f.element });
    const fresh = resolveScriptTarget({ selector: "button" }, "private");
    expect(fresh.token).not.toBe(old.token);
    expect(resolveScriptTarget({ selector: "button" }, "private", old.token, true).error).toBe("STALE_TARGET");
    expect(f.element.events).toEqual([]);
  });
  it("refuses a traversal budget overflow without materializing all candidates", () => {
    const f = fixture(6000);
    f.element.matches = () => false;
    expect(resolveScriptTarget({ selector: "missing" }, "private").error).toBe("TARGET_QUERY_LIMIT");
  });
});

describe("bounded accessible names", () => {
  it("refuses more than32 labelled-by references instead of matching a truncated prefix", () => {
    class Button extends ElementStub {
      tagName = "BUTTON";
      getAttribute(name: string) { return name === "aria-labelledby" ? Array.from({ length: 33 }, (_, i) => "id" + String(i)).join(" ") : null; }
      hasAttribute() { return false; }
    }
    fixture(1, new Button());
    expect(resolveScriptTarget({ role: "button", name: "prefix", exact: true }, "private").error).toBe("TARGET_QUERY_LIMIT");
  });
  it("counts empty descendants in the accessible-name traversal budget", () => {
    class Button extends ElementStub {
      tagName = "BUTTON";
      getAttribute() { return null; }
      hasAttribute() { return false; }
    }
    const button = new Button();
    fixture(1, button);
    vi.stubGlobal("document", {
      documentElement: button,
      elementFromPoint: () => button,
      createTreeWalker: (_root: unknown, mask: number) => {
        let visits = 0;
        return { currentNode: button, nextNode: () => mask === 1 ? null : ++visits < 300 ? { nodeType: 1, textContent: "" } : null };
      },
    });
    expect(resolveScriptTarget({ role: "button", name: "missing", exact: true }, "private").error).toBe("TARGET_QUERY_LIMIT");
  });
});
