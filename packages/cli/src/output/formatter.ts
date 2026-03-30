import chalk from "chalk";
import Table from "cli-table3";
import type { OutputFormat, DiscoveredDevice } from "../types.js";

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
      .map(([k, v]) => `${k}: ${typeof v === "object" ? JSON.stringify(v) : v}`)
      .join("\n");
  }
  return String(data);
}

function formatTable(data: unknown): string {
  if (!data || typeof data !== "object") return formatText(data);

  // Device list
  if ("devices" in (data as Record<string, unknown>)) {
    const list = (data as { devices: DiscoveredDevice[] }).devices;
    return formatDeviceTable(list);
  }

  // Generic object
  const table = new Table();
  for (const [key, value] of Object.entries(data as Record<string, unknown>)) {
    table.push({ [key]: typeof value === "object" ? JSON.stringify(value) : String(value ?? "") });
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
      d.platform,
      d.model,
      d.ip,
      d.port,
      `${d.width}x${d.height}`,
      d.id.slice(0, 8) + "...",
    ]);
  }

  return table.toString();
}

export function print(data: unknown, format: OutputFormat): void {
  console.log(formatOutput(data, format));
}
