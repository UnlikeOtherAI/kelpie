import { BrowserControlError } from "./protocol.js";
import type { BrowserControlMethod, BrowserControlRequest, BrowserControlTransport, BrowserCapabilities, BrowserImage, BrowserLocator, BrowserSnapshot, BrowserTabInfo, BrowserTextMatcher } from "./protocol.js";

type Match = string | RegExp;
const match = (value: Match): BrowserTextMatcher => typeof value === "string" ? value : { source: value.source, flags: value.flags };
interface Wait { timeoutMs?: number }
type Select = string | { value?: string; label?: string; index?: number };
export class BrowserLocatorClient {
  constructor(private readonly tab: BrowserTabClient, private readonly query: BrowserLocator) {}
  private chain(query: BrowserLocator[number]): BrowserLocatorClient { return new BrowserLocatorClient(this.tab, [...this.query, query]); }
  getByRole(role: string, options: { name?: Match; exact?: boolean } = {}): BrowserLocatorClient { return this.chain({ kind: "role", role, ...options, name: options.name === undefined ? undefined : match(options.name) }); }
  getByLabel(value: Match, options: { exact?: boolean } = {}): BrowserLocatorClient { return this.chain({ kind: "label", value: match(value), ...options }); }
  getByText(value: Match, options: { exact?: boolean } = {}): BrowserLocatorClient { return this.chain({ kind: "text", value: match(value), ...options }); }
  getByPlaceholder(value: Match, options: { exact?: boolean } = {}): BrowserLocatorClient { return this.chain({ kind: "placeholder", value: match(value), ...options }); }
  getByTestId(value: Match): BrowserLocatorClient { return this.chain({ kind: "testId", value: match(value) }); }
  locator(value: string): BrowserLocatorClient { return this.chain({ kind: "css", value }); }
  frameLocator(value: string): BrowserLocatorClient { return this.chain({ kind: "frame", value }); }
  nth(index: number): BrowserLocatorClient { return this.chain({ kind: "nth", index }); }
  first(): BrowserLocatorClient { return this.nth(0); }
  last(): BrowserLocatorClient { return this.nth(-1); }
  filter(options: { hasText?: Match; visible?: boolean }): BrowserLocatorClient { return this.chain({ kind: "filter", ...options, hasText: options.hasText === undefined ? undefined : match(options.hasText) }); }
  private call<T>(method: BrowserControlMethod, params: object = {}): Promise<T> { return this.tab.call(method, { locator: this.query, ...params }); }
  click(options: Wait & { button?: "left" | "right" | "middle"; modifiers?: ("Alt" | "Control" | "ControlOrMeta" | "Meta" | "Shift")[] } = {}): Promise<void> { return this.call("locator.click", options); }
  dblclick(options: Wait = {}): Promise<void> { return this.call("locator.dblclick", options); }
  fill(value: string, options: Wait = {}): Promise<void> { return this.call("locator.fill", { value, ...options }); }
  type(text: string, options: Wait = {}): Promise<void> { return this.call("locator.type", { text, ...options }); }
  pressSequentially(text: string, options: Wait = {}): Promise<void> { return this.type(text, options); }
  press(key: string, options: Wait = {}): Promise<void> { return this.call("locator.press", { key, ...options }); }
  check(options: Wait = {}): Promise<void> { return this.call("locator.check", options); }
  uncheck(options: Wait = {}): Promise<void> { return this.call("locator.uncheck", options); }
  setChecked(checked: boolean, options: Wait = {}): Promise<void> { return checked ? this.check(options) : this.uncheck(options); }
  selectOption(value: Select | Select[], options: Wait = {}): Promise<string[]> { return this.call("locator.selectOption", { value, ...options }); }
  innerText(options: Wait = {}): Promise<string> { return this.call("locator.innerText", options); }
  textContent(options: Wait = {}): Promise<string | null> { return this.call("locator.textContent", options); }
  getAttribute(name: string, options: Wait = {}): Promise<string | null> { return this.call("locator.getAttribute", { name, ...options }); }
  count(): Promise<number> { return this.call("locator.count"); }
  isVisible(): Promise<boolean> { return this.call("locator.isVisible"); }
  isEnabled(): Promise<boolean> { return this.call("locator.isEnabled"); }
  waitFor(options: Wait & { state?: "attached" | "detached" | "visible" | "hidden" } = {}): Promise<void> { return this.call("locator.waitFor", options); }
}
export class BrowserTabClient {
  readonly playwright;
  constructor(readonly id: string, private readonly transport: BrowserControlTransport) {
    const root = new BrowserLocatorClient(this, []);
    this.playwright = {
      domSnapshot: async (): Promise<string> => (await this.snapshot()).text,
      getByRole: root.getByRole.bind(root), getByLabel: root.getByLabel.bind(root), getByText: root.getByText.bind(root),
      getByPlaceholder: root.getByPlaceholder.bind(root), getByTestId: root.getByTestId.bind(root),
      locator: root.locator.bind(root), frameLocator: root.frameLocator.bind(root),
    };
  }
  async call<T>(method: BrowserControlMethod, params: object = {}): Promise<T> {
    const answer = await this.transport.call({ version: 1, method, tabId: this.id, params } as BrowserControlRequest);
    if (!answer.ok) throw new BrowserControlError(answer.error.code, answer.error.message, answer.error.mayHaveCompleted);
    return answer.value as T;
  }
  goto(url: string, options: Wait = {}): Promise<void> { return this.call("tab.goto", { url, ...options }); }
  back(): Promise<void> { return this.call("tab.back"); }
  forward(): Promise<void> { return this.call("tab.forward"); }
  reload(): Promise<void> { return this.call("tab.reload"); }
  close(): Promise<void> { return this.call("tabs.close"); }
  url(): Promise<string> { return this.call("tab.url"); }
  title(): Promise<string> { return this.call("tab.title"); }
  snapshot(options: { maxElements?: number; maxChars?: number } = {}): Promise<BrowserSnapshot> { return this.call("tab.snapshot", options); }
  async getAXState(): Promise<string> { return (await this.snapshot()).text; }
  async screenshot(options: { fullPage?: boolean; format?: "png" | "jpeg"; quality?: number } = {}): Promise<Uint8Array> {
    const image = await this.call<BrowserImage>("tab.screenshot", options);
    return Uint8Array.from(atob(image.data), (character) => character.charCodeAt(0));
  }
  getScreenshot(): Promise<Uint8Array> { return this.screenshot(); }
  click(ref: string | number): Promise<void> { return this.call("tab.click", { ref: String(ref) }); }
  typeText(ref: string | number | null, text: string): Promise<void> {
    if (ref === null) return Promise.reject(new BrowserControlError("UNSUPPORTED_OPERATION", "Focused typing is not in the supported browser subset."));
    return this.call("tab.type", { ref: String(ref), text });
  }
  pressKey(key: string): Promise<void>;
  pressKey(ref: string | number | null, key: string): Promise<void>;
  pressKey(refOrKey: string | number | null, key?: string): Promise<void> {
    if (key !== undefined && refOrKey !== null) return Promise.reject(new BrowserControlError("UNSUPPORTED_OPERATION", "Observed-reference key presses are not supported."));
    return this.call("page.press", { key: key ?? refOrKey });
  }
  scroll(deltaY: number, deltaX = 0): Promise<void> { return this.call("page.scroll", { deltaX, deltaY }); }
}
export function createBrowserClient(transport: BrowserControlTransport) {
  const call = async <T>(request: BrowserControlRequest): Promise<T> => {
    const answer = await transport.call(request);
    if (!answer.ok) throw new BrowserControlError(answer.error.code, answer.error.message, answer.error.mayHaveCompleted);
    return answer.value as T;
  };
  return {
    tabs: {
      list: (): Promise<BrowserTabInfo[]> => call({ version: 1, method: "tabs.list", params: {} }),
      select: (id: string): Promise<void> => call({ version: 1, method: "tabs.select", tabId: id, params: {} }),
      get: (id: string): Promise<BrowserTabClient> => Promise.resolve(new BrowserTabClient(id, transport)),
      new: async (options: { url?: string } = {}): Promise<BrowserTabClient> => {
        const tab = await call<BrowserTabInfo>({ version: 1, method: "tabs.new", params: options });
        return new BrowserTabClient(tab.id, transport);
      },
    },
    documentation: (): Promise<string> => call({ version: 1, method: "documentation", params: {} }),
    capabilities: (): Promise<BrowserCapabilities> => call({ version: 1, method: "capabilities", params: {} }),
  };
}
