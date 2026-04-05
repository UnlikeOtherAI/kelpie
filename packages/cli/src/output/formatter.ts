import chalk from "chalk";
import Table from "cli-table3";
import type { OutputFormat, DiscoveredDevice } from "../types.js";

function stringify(value: unknown): string {
  if (value === null || value === undefined) return "";
  if (typeof value === "object") return JSON.stringify(value);
  return String(value as string | number | boolean);
}

function formatPlatform(device: DiscoveredDevice): string {
  if (device.platform === "linux" && device.runtimeMode) {
    return `${device.platform} (${device.runtimeMode})`;
  }
  return device.platform;
}

export function formatOutput(data: unknown, format: OutputFormat): string {
  switch (format) {
    case "json":
      return JSON.stringify(data, null, 2);
    case "text":
      return formatText(data);
    case "table":
      return formatTable(data);
  }
}

function formatText(data: unknown): string {
  if (typeof data === "string") return data;
  if (data === null || data === undefined) return "";
  if (typeof data === "object") {
    return Object.entries(data as Record<string, unknown>)
      .map(([k, v]) => `${k}: ${stringify(v)}`)
      .join("\n");
  }
  return stringify(data);
}

function formatTable(data: unknown): string {
  if (!data || typeof data !== "object") return formatText(data);

  // Device list
  if ("devices" in (data as Record<string, unknown>)) {
    const list = (data as { devices: DiscoveredDevice[] }).devices;
    return formatDeviceTable(list);
  }

  if ("browsers" in (data as Record<string, unknown>)) {
    const list = (data as { browsers: Record<string, unknown>[] }).browsers;
    return formatBrowserTable(list);
  }

  // Generic object
  const table = new Table();
  for (const [key, value] of Object.entries(data as Record<string, unknown>)) {
    table.push({ [key]: stringify(value) });
  }
  return table.toString();
}

export function formatDeviceTable(devices: DiscoveredDevice[]): string {
  if (devices.length === 0) return chalk.yellow("No devices found");

  const table = new Table({
    head: ["Name", "Platform", "Model", "IP", "Port", "Resolution", "ID"],
    style: { head: ["cyan"] },
  });

  for (const d of devices) {
    table.push([
      d.name,
      formatPlatform(d),
      d.model,
      d.ip,
      d.port,
      `${String(d.width)}x${String(d.height)}`,
      d.id.slice(0, 8) + "...",
    ]);
  }

  return table.toString();
}

function formatBrowserTable(browsers: Record<string, unknown>[]): string {
  if (browsers.length === 0) return chalk.yellow("No browsers found");

  const table = new Table({
    head: ["Name", "Platform", "Port", "Reachable", "App Path", "Last Launched"],
    style: { head: ["cyan"] },
  });

  for (const browser of browsers) {
    table.push([
      stringify(browser.name),
      stringify(browser.platform),
      stringify(browser.port),
      stringify(browser.reachable),
      stringify(browser.appPath),
      stringify(browser.lastLaunchedAt),
    ]);
  }

  return table.toString();
}

export function print(data: unknown, format: OutputFormat): void {
  console.log(formatOutput(data, format));
}
