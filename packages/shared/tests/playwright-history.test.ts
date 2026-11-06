import { EventEmitter } from "node:events";
import type { Page } from "playwright-core";
import { describe, expect, it, vi } from "vitest";
import { navigateHistory } from "../src/browser-control/history.js";
import { executePlaywrightPage } from "../src/browser-control/playwright.js";

function fixture(options: { navigate?: boolean; iframe?: boolean; replace?: boolean; same?: boolean; advance?: number; response?: boolean; finalAdvance?: number } = {}) {
  const emitter = new EventEmitter(), main = {}, child = {};
  let time = 0;
  const documentHandle = { evaluate: vi.fn(async () => { time += options.finalAdvance ?? 0; return options.same !== false; }), dispose: vi.fn(async () => undefined) };
  const readyHandle = { dispose: vi.fn(async () => undefined) };
  const dispatch = vi.fn(async () => {
    if (options.iframe) emitter.emit("framenavigated", child);
    if (options.navigate) emitter.emit("framenavigated", main);
    time += options.advance ?? 0;
    return options.response ? {} : null;
  });
  const evaluateHandle = vi.fn(async () => documentHandle);
  const waitForFunction = vi.fn(async (..._args: unknown[]) => {
    if (options.replace) emitter.emit("framenavigated", main);
    return readyHandle;
  });
  const page = {
    mainFrame: () => main,
    on: emitter.on.bind(emitter), off: emitter.off.bind(emitter),
    goBack: dispatch, goForward: dispatch, evaluateHandle, waitForFunction,
  } as unknown as Page;
  return { page, dispatch, evaluateHandle, waitForFunction, documentHandle, readyHandle, emitter, now: () => time };
}

describe("single-budget history navigation", () => {
  it("returns immediately without history and ignores iframe navigation", async () => {
    const f = fixture({ iframe: true });
    await navigateHistory(f.page, "back", 100, f.now);
    expect(f.dispatch).toHaveBeenCalledOnce();
    expect(f.dispatch).toHaveBeenCalledWith({ waitUntil: "commit", timeout: 100 });
    expect(f.evaluateHandle).not.toHaveBeenCalled();
    expect(f.emitter.listenerCount("framenavigated")).toBe(0);
  });
  it("checks the exact resulting main-frame document after a single same-document-capable dispatch", async () => {
    const f = fixture({ navigate: true, iframe: true, advance: 30 });
    await navigateHistory(f.page, "forward", 100, f.now);
    expect(f.dispatch).toHaveBeenCalledOnce();
    expect(f.dispatch).toHaveBeenCalledWith({ waitUntil: "commit", timeout: 100 });
    expect(f.waitForFunction).toHaveBeenCalledOnce();
    expect(f.waitForFunction.mock.calls[0][2]).toEqual({ timeout: 70 });
    expect(f.documentHandle.evaluate).toHaveBeenCalledOnce();
    expect(f.emitter.listenerCount("framenavigated")).toBe(0);
  });
  it("rejects main-frame replacement or a stale document without retry", async () => {
    for (const options of [{ navigate: true, replace: true }, { navigate: true, same: false }]) {
      const f = fixture(options);
      await expect(navigateHistory(f.page, "back", 100, f.now)).rejects.toMatchObject({
        code: "HISTORY_DOCUMENT_CHANGED", mayHaveCompleted: true,
      });
      expect(f.dispatch).toHaveBeenCalledOnce();
      expect(f.emitter.listenerCount("framenavigated")).toBe(0);
    }
  });
  it("uses one deadline and does not start readiness when the budget is exhausted", async () => {
    const f = fixture({ navigate: true, advance: 101 });
    await expect(navigateHistory(f.page, "back", 100, f.now)).rejects.toMatchObject({
      code: "TIMEOUT", mayHaveCompleted: true,
    });
    expect(f.dispatch).toHaveBeenCalledOnce();
    expect(f.evaluateHandle).not.toHaveBeenCalled();
  });
  it("keeps the existing no-deadline meaning of timeout zero", async () => {
    const f = fixture({ navigate: true, advance: 101 });
    await navigateHistory(f.page, "back", 0, f.now);
    expect(f.dispatch).toHaveBeenCalledWith({ waitUntil: "commit", timeout: 0 });
    expect(f.waitForFunction.mock.calls[0][2]).toEqual({ timeout: 0 });
  });
});

it("keeps the restricted adapter's default DOMContentLoaded history behavior", async () => {
  const f = fixture({ navigate: true });
  await executePlaywrightPage(f.page, { version: 1, method: "tab.back", tabId: "a", params: {} });
  expect(f.dispatch).toHaveBeenCalledOnce();
  expect(f.dispatch).toHaveBeenCalledWith({ waitUntil: "domcontentloaded", timeout: 10_000 });
  expect(f.evaluateHandle).not.toHaveBeenCalled();
});
it("rejects a non-null history response without a main-frame observation", async () => {
  const f = fixture({ response: true });
  await expect(navigateHistory(f.page, "back", 100, f.now)).rejects.toMatchObject({
    code: "HISTORY_OBSERVATION_MISSING", mayHaveCompleted: true,
  });
  expect(f.dispatch).toHaveBeenCalledOnce();
  expect(f.evaluateHandle).not.toHaveBeenCalled();
});

it("does not acknowledge a no-history or final success after the deadline", async () => {
  const noHistory = fixture({ advance: 101 });
  await expect(navigateHistory(noHistory.page, "back", 100, noHistory.now)).rejects.toMatchObject({
    code: "TIMEOUT", mayHaveCompleted: true,
  });
  const final = fixture({ navigate: true, finalAdvance: 101 });
  await expect(navigateHistory(final.page, "forward", 100, final.now)).rejects.toMatchObject({
    code: "TIMEOUT", mayHaveCompleted: true,
  });
  expect(noHistory.dispatch).toHaveBeenCalledOnce();
  expect(final.dispatch).toHaveBeenCalledOnce();
});
