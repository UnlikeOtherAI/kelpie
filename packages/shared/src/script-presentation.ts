export interface ScriptPoint { x: number; y: number }
export interface ScriptMotion {
  from: ScriptPoint;
  to: ScriptPoint;
  curve: "s" | "c";
}
/** Presentation only: never dispatches pointer movement or hover events. */
export function scriptPointerPosition(motion: ScriptMotion, progress: number): ScriptPoint {
  const t0 = Number.isNaN(progress) ? 0 : Math.min(1, Math.max(0, progress));
  const t = t0 * t0 * (3 - 2 * t0);
  const dx = motion.to.x - motion.from.x;
  const dy = motion.to.y - motion.from.y;
  const distance = Math.hypot(dx, dy);
  const amplitude = Math.min(80, distance * 0.18);
  const nx = distance ? -dy / distance * amplitude : 0;
  const ny = distance ? dx / distance * amplitude : 0;
  const sign = motion.curve === "s" ? -1 : 1;
  const a = { x: motion.from.x + dx / 3 + nx, y: motion.from.y + dy / 3 + ny };
  const b = { x: motion.from.x + dx * 2 / 3 + nx * sign, y: motion.from.y + dy * 2 / 3 + ny * sign };
  const u = 1 - t;
  return {
    x: u ** 3 * motion.from.x + 3 * u ** 2 * t * a.x + 3 * u * t ** 2 * b.x + t ** 3 * motion.to.x,
    y: u ** 3 * motion.from.y + 3 * u ** 2 * t * a.y + 3 * u * t ** 2 * b.y + t ** 3 * motion.to.y,
  };
}
/** Native display and frame compositor use the same numeric timeline. */
export function scriptTapPresentation(progress: number, wobble = true, fade = true): { scale: number; alpha: number } {
  const t = Number.isNaN(progress) ? 0 : Math.min(1, Math.max(0, progress));
  return { scale: wobble ? 1 + 0.12 * Math.sin(6 * Math.PI * t) * (1 - t) : 1, alpha: fade ? 1 - t : t < 1 ? 1 : 0 };
}

/** Zero/non-positive duration finishes immediately; NaN is a safe initial state. */
export function scriptTimelineProgress(elapsedMs: number, durationMs: number): number {
  if (Number.isNaN(durationMs)) return 0;
  if (durationMs <= 0) return 1;
  const progress = elapsedMs / durationMs;
  return Number.isNaN(progress) ? 0 : Math.min(1, Math.max(0, progress));
}