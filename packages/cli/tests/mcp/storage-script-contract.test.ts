import { describe, expect, it } from "vitest";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

interface Storage {
  length: number;
  key(index: number): string | null;
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  clear(): void;
}
function memory(entries: Record<string, string>): Storage {
  const values = new Map(Object.entries(entries));
  return { get length() { return values.size; }, key: (index) => [...values.keys()][index] ?? null,
    getItem: (key) => values.get(key) ?? null, setItem: (key, value) => { values.set(key, value); }, clear: () => values.clear() };
}
function run(expression: string, storage: Storage, sessionStorage = storage): unknown {
  // Storage scripts execute inside the browser; this mock supplies the Web Storage contract.
  // eslint-disable-next-line @typescript-eslint/no-implied-eval
  return new Function("window", "localStorage", "sessionStorage", `return ${expression};`)(
    { localStorage: storage, sessionStorage }, storage, sessionStorage,
  );
}

describe("desktop storage expressions", () => {
  it("uses quoted storage types and executes list, key, set, and clear forms", async () => {
    const source = await readFile(resolve("../../native/engine-chromium-desktop/src/handlers/cookie_handler.cpp"), "utf8");
    expect(source).toContain("const std::string type_literal = JsStringLiteral(type)");
    expect(source).not.toContain('return {type:"" + type + ""');
    const storage = memory({ language: "en" });
    const session = memory({ draft: "one" });
    const list = run("(() => { const s=window.localStorage; const e={}; for(let i=0;i<s.length;i++){const k=s.key(i);e[k]=s.getItem(k);} return {type:\"local\",entries:e,count:Object.keys(e).length}; })()", storage);
    expect(list).toEqual({ type: "local", entries: { language: "en" }, count: 1 });
    const keyed = run("(() => { const s=window.localStorage; const k=\"language\"; const v=s.getItem(k); return {type:\"local\",entries:v===null?{}:{[k]:v},count:v===null?0:1}; })()", storage);
    expect(keyed).toEqual({ type: "local", entries: { language: "en" }, count: 1 });
    expect(run("(() => { window.localStorage.setItem(\"theme\",\"dark\"); return {type:\"local\",key:\"theme\"}; })()", storage)).toEqual({ type: "local", key: "theme" });
    expect(run("(() => { window.localStorage.clear(); return {cleared:\"local\"}; })()", storage)).toEqual({ cleared: "local" });
    expect(run("(() => { const s=window.sessionStorage; const e={}; for(let i=0;i<s.length;i++){const k=s.key(i);e[k]=s.getItem(k);} return {type:\"session\",entries:e,count:Object.keys(e).length}; })()", session)).toEqual({ type: "session", entries: { draft: "one" }, count: 1 });
    run("(() => { localStorage.clear(); sessionStorage.clear(); return {cleared:'both'}; })()", storage, session);
    expect(storage.length).toBe(0);
    expect(session.length).toBe(0);
  });
});
