import type { Platform } from "@unlike-other-ai/mollotov-shared";

export interface DiscoveredDevice {
  id: string;
  name: string;
  ip: string;
  port: number;
  platform: Platform;
  model: string;
  width: number;
  height: number;
  version: string;
  lastSeen: number;
}

export interface GlobalOptions {
  device?: string;
  format: "json" | "table" | "text";
  timeout: number;
  port: number;
}

export type OutputFormat = GlobalOptions["format"];
