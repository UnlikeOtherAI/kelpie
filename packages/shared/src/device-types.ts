export type Platform = "ios" | "android";

export interface MdnsTxtRecord {
  id: string;
  name: string;
  model: string;
  platform: Platform;
  width: string;
  height: string;
  port: string;
  version: string;
}

export interface DeviceDisplay {
  width: number;
  height: number;
  physicalWidth: number;
  physicalHeight: number;
  devicePixelRatio: number;
  orientation: "portrait" | "landscape";
  refreshRate: number | null;
  screenDiagonal: number | null;
  safeAreaInsets: { top: number; bottom: number; left: number; right: number } | null;
}

export interface DeviceNetwork {
  ip: string;
  port: number;
  mdnsName: string;
  networkType: string;
  ssid: string | null;
}

export interface DeviceBrowser {
  engine: string;
  engineVersion: string;
  userAgent: string;
  viewportWidth: number;
  viewportHeight: number;
}

export interface DeviceApp {
  version: string;
  build: string;
  httpServerActive: boolean;
  mcpServerActive: boolean;
  mdnsActive: boolean;
  uptime: number;
}

export interface DeviceSystem {
  locale: string;
  timezone: string;
  batteryLevel: number | null;
  batteryCharging: boolean | null;
  thermalState: string | null;
  availableMemory: number | null;
  totalMemory: number | null;
}

export interface DeviceInfoFull {
  device: {
    id: string;
    name: string;
    model: string;
    manufacturer: string;
    platform: Platform;
    osName: string;
    osVersion: string;
    osBuild: string | null;
    architecture: string | null;
    isSimulator: boolean;
    isTablet: boolean;
  };
  display: DeviceDisplay;
  network: DeviceNetwork;
  browser: DeviceBrowser;
  app: DeviceApp;
  system: DeviceSystem;
}

export interface DeviceCapabilities {
  success: true;
  version: string;
  platform: Platform;
  supported: string[];
  partial: string[];
  unsupported: string[];
}
