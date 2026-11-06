// Auxiliary callbacks can arrive from different threads; their order is not constrained.
const names = new Set(["CONTEXT_INITIALIZED", "SCHEDULE_FIRST", "GTK_PUMP_FIRST"]);
export function parseGtkStartupAux(stderr, startup, truncated) {
  if (typeof truncated !== "boolean") return { state: "invalid", events: [] };
  const lines = stderr.split("\n");
  const aux = lines.filter(line => line.startsWith("KELPIE_GTK_AUX"));
  if (aux.length > 3) return { state: "invalid", events: [] };
  const anchors = lines.map(line => /^KELPIE_GTK_STARTUP FIRST_BROWSER_ENTER ([0-9]{1,20})$/.exec(line)).filter(Boolean);
  const anchor = startup?.state === "valid-prefix" && anchors.length === 1 &&
    startup.events.some(event => event.name === "FIRST_BROWSER_ENTER") ? BigInt(anchors[0][1]) : null;
  const events = [], seen = new Set();
  for (const line of aux) {
    const match = /^KELPIE_GTK_AUX ([A-Z_]+) ([0-9]{1,20})$/.exec(line);
    if (!match || !names.has(match[1]) || seen.has(match[1])) return { state: "invalid", events: [] };
    seen.add(match[1]);
    events.push({ name: match[1], relativeToFirstBrowserNs: anchor === null ? null : (BigInt(match[2]) - anchor).toString() });
  }
  return { state: truncated || startup?.state !== "valid-prefix" ? "incomplete" : events.length ? "observed" : "not-observed", events };
}
