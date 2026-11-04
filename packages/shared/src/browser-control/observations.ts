import { z } from "zod";

const selector = z.string().min(1).max(1024);
export const BrowserSnapshotOptionsSchema = z.object({
  maxElements: z.number().int().min(1).max(1000).optional(),
  maxChars: z.number().int().min(256).max(100_000).optional(),
  scope: selector.optional(), prioritize: z.boolean().optional(),
}).strict().default({});
export interface BrowserExtractionField {
  name: string; selector: string; source: "text" | "href" | "src" | "datetime";
  multiple?: boolean; fields?: BrowserExtractionField[];
}
const extractionField = (depth: number): z.ZodType<BrowserExtractionField> => {
  const base = z.object({
    name: z.string().min(1).max(80), selector,
    source: z.enum(["text", "href", "src", "datetime"]).default("text"),
    multiple: z.boolean().optional(),
  }).strict();
  return depth === 0 ? base : base.extend({ fields: z.array(extractionField(depth - 1)).min(1).max(16).optional() });
};
export const BrowserExtractionOptionsSchema = z.object({
  scope: selector.optional(),
  fields: z.array(extractionField(2)).min(1).max(32),
  metadata: z.boolean().optional(),
  maxChars: z.number().int().min(256).max(16_000).optional(),
}).strict();
export const BrowserReadinessOptionsSchema = z.object({
  state: z.enum(["interactive", "complete"]).default("interactive"),
  selector: selector.optional(),
}).strict().default({ state: "interactive" });
export type BrowserSnapshotOptions = z.infer<typeof BrowserSnapshotOptionsSchema>;
export type BrowserExtractionOptions = z.infer<typeof BrowserExtractionOptionsSchema>;
export type BrowserReadinessOptions = z.infer<typeof BrowserReadinessOptionsSchema>;
export interface BrowserExtractedField {
  name: string; status: "ok" | "missing" | "ambiguous" | "incomplete"; values: string[];
  records?: BrowserExtractedField[][];
  provenance: { selector: string; source: "text" | "href" | "src" | "datetime"; matches: number; matchesLimited?: boolean };
}
export interface BrowserExtraction {
  url: string; documentRevision: { availability: "unavailable" }; fields: BrowserExtractedField[]; truncated: boolean;
  metadata: { key: string; value: string; selector: string; attribute: string; authority: "publisher-claim" }[];
}
export interface BrowserPageStatus {
  url: string; title: string; documentState: DocumentReadyState; visibility: DocumentVisibilityState;
  network: { availability: "unavailable" }; errors: { availability: "unavailable" };
  viewport: { width: number; height: number }; dialogs: number; busyRegions: number; invalidControls: number; truncated: boolean;
}
export interface BrowserReadiness {
  ready: boolean; documentState: DocumentReadyState; requestedState: "interactive" | "complete";
  selector?: string; matches?: number; visible?: boolean;
}

/** Fixed reader: no caller code, form values, arbitrary attributes or network activity. */
export function collectBrowserExtraction(options: BrowserExtractionOptions): BrowserExtraction {
  let remaining = options.maxChars ?? 8000;
  let truncated = false;
  const bounded = (value: string): string => {
    const clean = value.replace(/\s+/g, " ").trim();
    const length = Math.min(remaining, 2048);
    if (clean.length > length) truncated = true;
    const output = clean.slice(0, length); remaining -= output.length; return output;
  };
  const excluded = "input,textarea,select,option,[contenteditable]:not([contenteditable='false']),script,style,noscript,template,[hidden],[aria-hidden='true']";
  const readable = (el: Element): boolean => !el.closest(excluded) && el.getClientRects().length > 0 &&
    getComputedStyle(el).visibility !== "hidden" && getComputedStyle(el).visibility !== "collapse";
  let visited = 0;
  const publicText = (node: Node, depth = 0): string => {
    if (++visited > 10_000 || depth > 40) { truncated = true; return ""; }
    if (node instanceof Element && (!readable(node) || node.matches(excluded))) return "";
    if (node.nodeType === Node.TEXT_NODE) {
      if ((node.textContent?.length ?? 0) > 2048) truncated = true;
      return (node.textContent ?? "").slice(0, 2048);
    }
    let output = "";
    for (const child of node.childNodes) {
      if (visited >= 10_000) { truncated = true; break; }
      output += " " + publicText(child, depth + 1);
      if (output.length > 4096) { truncated = true; break; }
    }
    return output.slice(0, 4096);
  };
  const scopes = options.scope ? document.querySelectorAll(options.scope) : [document];
  const root = scopes[0];
  if (scopes.length !== 1 || !root) throw new Error("OBSERVATION_SCOPE");
  let recordsRemaining = 100, fieldsRemaining = 512;
  const extract = (scope: Document | Element, field: BrowserExtractionField): BrowserExtractedField => {
    const all = scope.querySelectorAll(field.selector);
    const matches = Array.from(all).slice(0, 5000).filter(readable);
    if (all.length > 5000) truncated = true;
    const status = all.length > 5000 && (!field.multiple || matches.length === 0) ? "incomplete" : matches.length === 0 ? "missing" : !field.multiple && matches.length !== 1 ? "ambiguous" : "ok";
    const limit = field.fields ? recordsRemaining : 100;
    const selected = status === "ok" ? matches.slice(0, limit) : [];
    if (matches.length > limit) truncated = true;
    if (field.fields) recordsRemaining -= selected.length;
    const nestedFields = field.fields;
    const records = nestedFields ? selected.map((el) => nestedFields.flatMap((nested) => {
      if (--fieldsRemaining < 0) { truncated = true; return []; }
      return [extract(el, nested)];
    })) : undefined;
    const values = field.fields ? [] : selected.map((el) => bounded(field.source === "text" ? publicText(el) : el.getAttribute(field.source) ?? ""));
    return { name: field.name, status, values, ...(records ? { records } : {}), provenance: { selector: field.selector, source: field.source, matches: matches.length, ...(all.length > 5000 ? { matchesLimited: true } : {}) } };
  };
  const fields = options.fields.map((field) => extract(root, field));
  const metadata: BrowserExtraction["metadata"] = [];
  if (options.metadata) {
    const sources: [string, string, string][] = [
      ["canonical", "link[rel='canonical']", "href"], ["description", "meta[name='description']", "content"],
      ["author", "meta[name='author']", "content"], ["publisher", "meta[property='og:site_name']", "content"],
      ["publishedTime", "meta[property='article:published_time']", "content"],
      ["title", "meta[property='og:title']", "content"],
    ];
    for (const [key, selector, attribute] of sources) {
      const nodes = document.querySelectorAll(selector);
      for (const el of Array.from(nodes).slice(0, 4)) {
        const value = bounded(el.getAttribute(attribute) ?? "");
        if (value) metadata.push({ key, value, selector, attribute, authority: "publisher-claim" });
      }
      if (nodes.length > 4) truncated = true;
    }
  }
  if (options.metadata) {
    let jsonBudget = 65_536;
    const scripts = document.querySelectorAll("script[type='application/ld+json']");
    if (scripts.length > 8) truncated = true;
    for (const script of Array.from(scripts).slice(0, 8)) {
      const path: string[] = [];
      for (let el: Element | null = script; el; el = el.parentElement) {
        if (path.length >= 40) { truncated = true; break; }
        const position = el.parentElement ? Array.from(el.parentElement.children).indexOf(el) + 1 : 1;
        path.unshift(el.tagName.toLowerCase() + ":nth-child(" + String(position) + ")");
      }
      const scriptPath = path.join(" > ");
      const raw = script.textContent;
      if (raw.length > 32_768 || raw.length > jsonBudget) { truncated = true; continue; }
      jsonBudget -= raw.length;
      let parsed: unknown;
      try { parsed = JSON.parse(raw) as unknown; } catch { continue; }
      const roots: unknown[] = Array.isArray(parsed) ? parsed : [parsed];
      const queue = roots.slice(0, 32).map((value, index) => ({ value, path: Array.isArray(parsed) ? "/" + String(index) : "" }));
      for (let n = 0; n < queue.length && n < 32; n++) {
        const item = queue[n];
        if (!item) continue;
        const node = item.value;
        if (!node || typeof node !== "object" || Array.isArray(node)) continue;
        const data = node as Record<string, unknown>;
        if (Array.isArray(data["@graph"])) {
          if (data["@graph"].length > 32 - queue.length) truncated = true;
          queue.push(...data["@graph"].slice(0, 32 - queue.length).map((value: unknown, index: number) => ({ value, path: item.path + "/@graph/" + String(index) })));
        }
        const add = (key: string, value: unknown, path: string): void => {
          if (Array.isArray(value)) {
            if (value.length > 8) truncated = true;
            for (const [index, item] of value.slice(0, 8).entries()) if (typeof item === "string") add(key, item, path + "/" + String(index));
            return;
          }
          if (typeof value !== "string") return;
          const result = bounded(value);
          if (result) metadata.push({ key, value: result, selector: scriptPath,
            attribute: "json:" + item.path + "/" + path, authority: "publisher-claim" });
        };
        for (const key of ["@type", "name", "headline", "datePublished", "dateModified", "url"]) add(key, data[key], key);
        for (const key of ["author", "publisher"]) {
          const people = Array.isArray(data[key]) ? data[key] : [data[key]];
          if (people.length > 8) truncated = true;
          for (const [index, person] of people.slice(0, 8).entries()) {
            const path = key + (Array.isArray(data[key]) ? "/" + String(index) : "");
            if (typeof person === "string") add(key, person, path);
            else if (person && typeof person === "object") add(key, (person as Record<string, unknown>).name, path + "/name");
          }
        }
      }
      if (roots.length > 32 || queue.length > 32) truncated = true;
    }
  }
  return { url: location.href.slice(0, 4096), documentRevision: { availability: "unavailable" }, fields, metadata, truncated };
}

/** Current document facts only; no listeners or inferred network/SPA readiness. */
export function collectBrowserPageStatus(): BrowserPageStatus {
  const visible = (el: Element): boolean => el.getClientRects().length > 0 && !el.closest("[hidden],[aria-hidden='true']") && getComputedStyle(el).visibility !== "hidden";
  let truncated = false;
  const count = (selector: string): number => {
    const nodes = document.querySelectorAll(selector);
    if (nodes.length > 5000) truncated = true;
    return Array.from(nodes).slice(0, 5000).filter(visible).length;
  };
  const dialogs = count("dialog[open],[role='dialog'],[role='alertdialog']");
  const busyRegions = count("[aria-busy='true']"), invalidControls = count("[aria-invalid='true']");
  return {
    url: location.href.slice(0, 4096), title: document.title.slice(0, 1024), documentState: document.readyState,
    visibility: document.visibilityState, network: { availability: "unavailable" }, errors: { availability: "unavailable" }, viewport: { width: innerWidth, height: innerHeight },
    dialogs, busyRegions, invalidControls, truncated,
  };
}

/** Immediate explicit predicate. Never equates document load with app readiness. */
export function collectBrowserReadiness(options: BrowserReadinessOptions): BrowserReadiness {
  const documentState = document.readyState;
  const loaded = options.state === "complete" ? documentState === "complete" : documentState !== "loading";
  if (!options.selector) return { ready: loaded, documentState, requestedState: options.state };
  const nodes = document.querySelectorAll(options.selector);
  const el = nodes.length === 1 ? nodes[0] : undefined;
  const visible = !!el && el.getClientRects().length > 0 && !el.closest("[hidden],[aria-hidden='true']") &&
    getComputedStyle(el).visibility !== "hidden" && getComputedStyle(el).visibility !== "collapse";
  return { ready: loaded && visible, documentState, requestedState: options.state, selector: options.selector, matches: nodes.length, visible };
}

