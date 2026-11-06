// Fixed-code parsing of bounded startup markers; never returns unrelated stderr.
const transitions = {
  GTK_INIT_ENTER: ["GTK_INIT_RETURN"], GTK_INIT_RETURN: ["SHOW_ENTER"],
  SHOW_ENTER: ["CANVAS_REALIZE", "SHOW_RETURN"], CANVAS_REALIZE: ["ATTACH_ENTER"],
  ATTACH_ENTER: ["START_ENTER"], START_ENTER: ["START_OK", "START_FAIL"],
  START_OK: ["PUBLISH_ENTER"], START_FAIL: ["ATTACH_FAIL"],
  PUBLISH_ENTER: ["PUBLISH_OK"], PUBLISH_OK: ["ATTACH_OK"],
  ATTACH_OK: ["SHOW_RETURN"], ATTACH_FAIL: ["SHOW_RETURN"], SHOW_RETURN: ["CANVAS_REALIZE"],
};
export function parseGtkStartupTrace(stderr) {
  const lines = stderr.split("\n").filter(line => line.startsWith("KELPIE_GTK_STARTUP "));
  if (!lines.length) return { state: "not-observed", events: [] };
  if (lines.length > 32) return { state: "invalid", events: [] };
  const events = [];
  let previous, first;
  const seen = new Set();
  for (const line of lines) {
    const match = /^KELPIE_GTK_STARTUP ([A-Z_]+) ([0-9]{1,20})$/.exec(line);
    if (!match || !(match[1] in transitions)) return { state: "invalid", events: [] };
    if (seen.has(match[1])) return { state: "invalid", events: [] };
    seen.add(match[1]);
    const time = BigInt(match[2]);
    if ((!previous && match[1] !== "GTK_INIT_ENTER") ||
        (previous && (!transitions[previous.name].includes(match[1]) || time < previous.time)))
      return { state: "invalid", events: [] };
    first ??= time;
    previous = { name: match[1], time };
    events.push({ name: match[1], elapsedNs: (time - first).toString() });
  }
  return { state: "valid-prefix", events };
}
