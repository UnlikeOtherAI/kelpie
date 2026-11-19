import type { DeviceCapabilities, Platform, RuntimeMode } from "@unlikeotherai/kelpie-shared";

export interface DiscoveredDevice {
  id: string;
  name: string;
  ip: string;
  port: number;
  platform: Platform;
  runtimeMode?: RuntimeMode;
  /** Renderer the instance reports (mDNS TXT `engine` / get-device-info), when known. */
  engine?: string;
  model: string;
  width: number;
  height: number;
  version: string;
  lastSeen: number;
  capabilities?: DeviceCapabilities;
  /** An address selector must stay on its chosen socket during auth retry. */
  explicitAddress?: boolean;
  /** Read from an ACL-protected local readiness file; never persisted or printed. */
  localControlToken?: string;
  localReadinessFile?: string;
  localLaunchId?: string;
}

/** One device can advertise several listeners, and one listener can answer on several IPs. */
export function discoveredDeviceKey(device: DiscoveredDevice): string {
  return `${device.id}:${device.port}`;
}

export interface GlobalOptions {
  device?: string;
  format: "json" | "table" | "text";
  timeout: number;
  port: number;
  browser?: string;
  tabId?: string;
  tabGeneration?: number;
}

export type OutputFormat = GlobalOptions["format"];
