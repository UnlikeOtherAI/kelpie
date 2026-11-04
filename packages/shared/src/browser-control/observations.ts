import { z } from "zod";
import { createBoundedDOMReader } from "./dom-reader.js";

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
  metadata: { key: string; value: string; selector: string; attribute: string; authority: "publisher-claim"; provenanceComplete: boolean; index?: number }[];
}
export interface BrowserPageStatus {
  url: string; title: string; documentState: DocumentReadyState; visibility: DocumentVisibilityState;
  network: { availability: "unavailable" }; errors: { availability: "unavailable" };
  viewport: { width: number; height: number }; dialogs: number; busyRegions: number; invalidControls: number; truncated: boolean;
}
export interface BrowserReadiness {
  ready: boolean; documentState: DocumentReadyState; requestedState: "interactive" | "complete";
  selector?: string; matches?: number; visible?: boolean; incomplete?: boolean; matchesLimited?: boolean;
}

/** Fixed deterministic reader using one shared traversal/text/style budget. */
export function collectBrowserExtraction(options: BrowserExtractionOptions, factory: typeof createBoundedDOMReader = createBoundedDOMReader): BrowserExtraction {
  const dom = factory();
  let remaining = options.maxChars ?? 8000, recordsRemaining = 100, fieldsRemaining = 512;
  const bounded = (value: string): string => {
    const output = dom.bounded(value, Math.min(remaining, 2048));
    remaining -= output.length; return output;
  };
  const root = dom.scope(options.scope);
  const extract = (scope: Document | Element, field: BrowserExtractionField): BrowserExtractedField => {
    const result = dom.scan(scope, field.selector, { readable: true, limit: field.multiple ? 101 : 2 });
    const count = result.found.length;
    const status = !field.multiple && count > 1 ? "ambiguous" : !result.complete && (!field.multiple || count === 0) ? "incomplete" : count === 0 ? "missing" : "ok";
    const limit = field.fields ? recordsRemaining : 100;
    const selected = status === "ok" ? result.found.slice(0, limit) : [];
    if (count > limit) dom.mark();
    if (field.fields) recordsRemaining -= selected.length;
    const nestedFields = field.fields;
    const records = nestedFields ? selected.map((el) => nestedFields.flatMap((nested) => {
      if (--fieldsRemaining < 0) { dom.mark(); return []; }
      return [extract(el, nested)];
    })) : undefined;
    const values = field.fields ? [] : selected.map((el) => bounded(field.source === "text" ? dom.text(el, Math.min(remaining, 2048)).value : dom.attr(el, field.source, Math.min(remaining, 2048))));
    return { name: field.name, status, values, ...(records ? { records } : {}), provenance: {
      selector: field.selector, source: field.source, matches: count, ...(!result.complete ? { matchesLimited: true } : {}),
    } };
  };
  const fields = options.fields.map((field) => extract(root, field));
  const metadata: BrowserExtraction["metadata"] = [];
  if (options.metadata) {
    const candidates = dom.scan(document, "meta,link,script[type='application/ld+json']", { limit: 128 });
    const sources: [string, string, string][] = [
      ["canonical", "link[rel='canonical']", "href"], ["description", "meta[name='description']", "content"],
      ["author", "meta[name='author']", "content"], ["publisher", "meta[property='og:site_name']", "content"],
      ["publishedTime", "meta[property='article:published_time']", "content"], ["title", "meta[property='og:title']", "content"],
    ];
    for (const [key, selector, attribute] of sources) {
      let index = 0;
      for (const el of candidates.found) {
        if (!el.matches(selector) || dom.state(el).editorAncestor || dom.state(el).unknown || (el.hasAttribute("contenteditable") && dom.attr(el, "contenteditable", 16) !== "false")) continue;
        if (index >= 4) { dom.mark(); break; }
        const value = bounded(dom.attr(el, attribute, Math.min(remaining, 2048)));
        if (value) metadata.push({ key, value, selector, attribute, authority: "publisher-claim",
          provenanceComplete: candidates.complete, ...(candidates.complete ? { index } : {}) });
        index++;
      }
    }
    let jsonBudget = 65_536, scriptIndex = 0;
    const scriptSelector = "script[type='application/ld+json']";
    for (const script of candidates.found) {
      if (!script.matches(scriptSelector) || dom.state(script).editorAncestor || dom.state(script).unknown || (script.hasAttribute("contenteditable") && dom.attr(script, "contenteditable", 16) !== "false")) continue;
      if (scriptIndex >= 8) { dom.mark(); break; }
      const index = scriptIndex++;
      const raw = dom.text(script, Math.min(32_768, jsonBudget), true, true);
      if (!raw.complete) continue;
      jsonBudget -= raw.value.length;
      let parsed: unknown;
      try { parsed = JSON.parse(raw.value) as unknown; } catch { continue; }
      const roots: unknown[] = Array.isArray(parsed) ? parsed : [parsed];
      const queue = roots.slice(0, 32).map((value, i) => ({ value, path: Array.isArray(parsed) ? "/" + String(i) : "" }));
      if (roots.length > 32) dom.mark();
      for (let n = 0; n < queue.length && n < 32; n++) {
        const item = queue[n];
        if (!item?.value || typeof item.value !== "object" || Array.isArray(item.value)) continue;
        const data = item.value as Record<string, unknown>;
        if (Array.isArray(data["@graph"])) {
          if (data["@graph"].length > 32 - queue.length) dom.mark();
          queue.push(...data["@graph"].slice(0, 32 - queue.length).map((value: unknown, i: number) => ({ value, path: item.path + "/@graph/" + String(i) })));
        }
        const add = (key: string, value: unknown, path: string): void => {
          if (Array.isArray(value)) {
            if (value.length > 8) dom.mark();
            for (let i = 0; i < Math.min(8, value.length); i++) if (typeof value[i] === "string") add(key, value[i], path + "/" + String(i));
            return;
          }
          if (typeof value !== "string") return;
          const result = bounded(value);
          if (result) metadata.push({ key, value: result, selector: scriptSelector, attribute: "json:" + item.path + "/" + path,
            authority: "publisher-claim", provenanceComplete: candidates.complete, ...(candidates.complete ? { index } : {}) });
        };
        for (const key of ["@type", "name", "headline", "datePublished", "dateModified", "url"]) add(key, data[key], key);
        for (const key of ["author", "publisher"]) {
          const people = Array.isArray(data[key]) ? data[key] : [data[key]];
          if (people.length > 8) dom.mark();
          for (let i = 0; i < Math.min(8, people.length); i++) {
            const person: unknown = people[i];
            const path = key + (Array.isArray(data[key]) ? "/" + String(i) : "");
            if (typeof person === "string") add(key, person, path);
            else if (person && typeof person === "object") add(key, (person as Record<string, unknown>).name, path + "/name");
          }
        }
      }
    }
  }
  return { url: location.href.slice(0, 4096), documentRevision: { availability: "unavailable" }, fields, metadata, truncated: dom.truncated };
}

/** Current DOM facts. Counts become lower bounds when the shared traversal budget is exhausted. */
export function collectBrowserPageStatus(factory: typeof createBoundedDOMReader = createBoundedDOMReader): BrowserPageStatus {
  const dom = factory();
  let dialogs = 0, busyRegions = 0, invalidControls = 0;
  const result = dom.scan(document, "dialog[open],[role='dialog'],[role='alertdialog'],[aria-busy='true'],[aria-invalid='true']");
  for (const el of result.found) {
    if (!dom.visible(el)) continue;
    if (el.matches("dialog[open],[role='dialog'],[role='alertdialog']")) dialogs++;
    if (dom.attr(el, "aria-busy", 16) === "true") busyRegions++;
    if (dom.attr(el, "aria-invalid", 16) === "true") invalidControls++;
  }
  const title = dom.title();
  return {
    url: location.href.slice(0, 4096), title, documentState: document.readyState, visibility: document.visibilityState,
    network: { availability: "unavailable" }, errors: { availability: "unavailable" },
    viewport: { width: innerWidth, height: innerHeight }, dialogs, busyRegions, invalidControls, truncated: dom.truncated,
  };
}

/** Immediate conservative predicate; incomplete searches never prove readiness. */
export function collectBrowserReadiness(options: BrowserReadinessOptions, factory: typeof createBoundedDOMReader = createBoundedDOMReader): BrowserReadiness {
  const documentState = document.readyState;
  const loaded = options.state === "complete" ? documentState === "complete" : documentState !== "loading";
  if (!options.selector) return { ready: loaded, documentState, requestedState: options.state };
  const dom = factory();
  const result = dom.scan(document, options.selector, { limit: 2 });
  const el = result.found.length === 1 ? result.found[0] : undefined;
  const visible = !!el && dom.visible(el, true);
  const incomplete = (!result.complete && result.found.length < 2) || (!!el && dom.state(el).unknown);
  return { ready: loaded && visible && !incomplete, documentState, requestedState: options.state,
    selector: options.selector, matches: result.found.length, visible, incomplete,
    ...(!result.complete ? { matchesLimited: true } : {}) };
}
