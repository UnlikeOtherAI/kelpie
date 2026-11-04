import { createBoundedDOMReader } from "./dom-reader.js";
import { collectBrowserSnapshot } from "./snapshot.js";
import { collectBrowserExtraction, collectBrowserPageStatus, collectBrowserReadiness } from "./observations.js";

export type FixedObservationKind = "snapshot" | "extract" | "status" | "ready";
/** Host-only composition of permanent readers; no caller source or arbitrary evaluation is accepted. */
export function fixedObservationReaderSource(kind: FixedObservationKind): string {
  const reader = { snapshot: collectBrowserSnapshot, extract: collectBrowserExtraction, status: collectBrowserPageStatus, ready: collectBrowserReadiness }[kind];
  const args = kind === "status" ? "createBoundedDOMReader" : "options,createBoundedDOMReader";
  // Supply the dependency explicitly: bundlers may rewrite imported names in collector defaults.
  return "function(options){const createBoundedDOMReader=(" + createBoundedDOMReader.toString() + ");return (" + reader.toString() + ")(" + args + ");}";
}
export function fixedObservationExpression(kind: FixedObservationKind, options: object = {}): string {
  return "(" + fixedObservationReaderSource(kind) + ")(" + JSON.stringify(options) + ")";
}
