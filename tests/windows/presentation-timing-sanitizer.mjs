const LINE=/^KELPIE_PRESENTATION_(LATCH|QUEUE) (\d{1,9}\.\d{3}) (\d{1,9}\.\d{3})(?: ([01]))?$/;
export function parsePresentationTiming(line) {
  if (line === "KELPIE_PRESENTATION_LATCH_TRUNCATED") return {kind:"latch",truncated:true};
  if (line === "KELPIE_PRESENTATION_QUEUE_TRUNCATED") return {kind:"queue",truncated:true};
  const match=LINE.exec(line);
  if (!match || (match[1]==="LATCH" && match[4]!==undefined) ||
      (match[1]==="QUEUE" && match[4]===undefined)) return null;
  const elapsedMs=Number(match[2]),durationMs=Number(match[3]);
  if (!Number.isFinite(elapsedMs) || !Number.isFinite(durationMs) ||
      elapsedMs>300000 || durationMs>300000) return null;
  return {kind:match[1].toLowerCase(),elapsedMs,durationMs,
    ...(match[4]===undefined ? {} : {latched:match[4]==="1"})};
}