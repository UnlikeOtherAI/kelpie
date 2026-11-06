// Auxiliary callbacks can arrive from different threads; their order is not constrained.
const names = new Set(["CONTEXT_INITIALIZED", "SCHEDULE_FIRST", "GTK_PUMP_FIRST",
  "AFTER_CREATED_ENTER_UI", "AFTER_CREATED_ENTER_OTHER", "AFTER_CREATED_RETURN_UI", "AFTER_CREATED_RETURN_OTHER"]);
export function parseGtkStartupAux(stderr, startup, truncated, expectedPid) {
  if (typeof truncated !== "boolean" || !Number.isInteger(expectedPid) || expectedPid <= 1)
    return { state: "invalid", events: [] };
  const lines = stderr.split("\n");
  const aux = lines.filter(line => line.startsWith("KELPIE_GTK_AUX"));
  if (aux.length > 5) return { state: "invalid", events: [] };
  const anchors = lines.map(line => /^KELPIE_GTK_STARTUP FIRST_BROWSER_ENTER ([0-9]{1,20})$/.exec(line)).filter(Boolean);
  const anchor = startup?.state === "valid-prefix" && anchors.length === 1 &&
    startup.events.some(event => event.name === "FIRST_BROWSER_ENTER") ? BigInt(anchors[0][1]) : null;
  const events = [], seen = new Set();
  let enter = null, returned = null;
  for (const line of aux) {
    const match = /^KELPIE_GTK_AUX ([A-Z_]+) ([0-9]{1,10}) ([0-9]{1,20})$/.exec(line);
    if (!match || !names.has(match[1]) || seen.has(match[1]) || Number(match[2]) !== expectedPid)
      return { state: "invalid", events: [] };
    seen.add(match[1]);
    const time = BigInt(match[3]);
    if (match[1].startsWith("AFTER_CREATED_ENTER_")) {
      if (enter !== null) return { state: "invalid", events: [] };
      enter = time;
    }
    if (match[1].startsWith("AFTER_CREATED_RETURN_")) {
      if (returned !== null) return { state: "invalid", events: [] };
      returned = time;
    }
    events.push({ name: match[1], relativeToFirstBrowserNs: anchor === null ? null : (time - anchor).toString() });
  }
  if (returned !== null && (enter === null || returned < enter)) return { state: "invalid", events: [] };
  return { state: truncated || startup?.state !== "valid-prefix" ? "incomplete" : events.length ? "observed" : "not-observed",
    pid: expectedPid, events };
}
