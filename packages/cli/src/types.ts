import type { DeviceCapabilities, Platform, RuntimeMode } from "@unlikeotherai/kelpie-shared";

export interface DiscoveredDevice {
  id: string;
  name: string;
  ip: string;
  port: number;
  platform: Platform;
  runtimeMode?: RuntimeMode;
  model: string;
  width: number;
  height: number;
  version: string;
  lastSeen: number;
  capabilities?: DeviceCapabilities;
}

export interface GlobalOptions {
  device?: string;
  format: "json" | "table" | "text";
  timeout: number;
  port: number;
  tabId?: string;
}

export type OutputFormat = GlobalOptions["format"];
