import type { DiscoveredDevice } from "../types.js";
import type { Platform } from "@unlikeotherai/kelpie-shared";
import { getDevice } from "../discovery/registry.js";

export interface FilterOptions {
  platform?: Platform;
  include?: string;
  exclude?: string;
}

export function filterDevices(
  devices: DiscoveredDevice[],
  opts: FilterOptions,
): DiscoveredDevice[] {
  let filtered = devices;

  if (opts.platform) {
    filtered = filtered.filter((d) => d.platform === opts.platform);
  }

  if (opts.include) {
    const targets = opts.include.split(",").map((s) => s.trim());
    filtered = filtered.filter((d) =>
      targets.some(
        (t) =>
          d.id === t ||
          d.name.toLowerCase() === t.toLowerCase() ||
          d.name.toLowerCase().includes(t.toLowerCase()),
      ),
    );
  }

  if (opts.exclude) {
    const excluded = opts.exclude.split(",").map((s) => s.trim().toLowerCase());
    filtered = filtered.filter(
      (d) =>
        !excluded.some(
          (e) => d.name.toLowerCase() === e || d.name.toLowerCase().includes(e),
        ),
    );
  }

  return filtered;
}
