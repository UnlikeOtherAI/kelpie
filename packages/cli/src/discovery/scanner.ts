import bonjourService from "bonjour-service";
import { networkInterfaces } from "node:os";
import {
  MDNS_SERVICE_TYPE,
  type MdnsTxtRecord,
  type Platform,
  type RuntimeMode,
} from "@unlikeotherai/kelpie-shared";
import { discoveredDeviceKey, type DiscoveredDevice } from "../types.js";

const platforms: readonly Platform[] = ["ios", "android", "macos", "linux", "windows"];
interface BonjourServiceRecord {
  txt?: Partial<MdnsTxtRecord>;
  addresses?: string[];
  referer?: { address?: string };
  name: string;
  port: number;
}

interface BonjourBrowser {
  on(event: "up" | "txt-update", listener: (service: BonjourServiceRecord) => void): void;
  stop(): void;
  /** Bonjour's browse transport; the public callback only covers replies sent by publishers. */
  mdns: {
    on(event: "error" | "warning", listener: (error: NodeJS.ErrnoException) => void): void;
    query(name: string, type: "PTR", callback: (error?: Error) => void): void;
  };
}

interface BonjourClient {
  find(opts: { type: string }): BonjourBrowser;
  destroy(): void;
}

type BonjourConstructor = new (options: { interface: string; bind: string }) => BonjourClient;
type BonjourModule = BonjourConstructor | { Bonjour?: BonjourConstructor; default?: BonjourConstructor };

function parsePlatform(value: string | undefined): Platform {
  const normalized = value?.toLowerCase();
  return platforms.find((platform) => platform === normalized) ?? "ios";
}

function parseRuntimeMode(value: string | undefined): RuntimeMode | undefined {
  const normalized = value?.toLowerCase();
  if (normalized === "gui" || normalized === "headless") {
    return normalized;
  }
  return undefined;
}

export interface MdnsInterface {
  address: string;
  error?: string;
}

export async function scanForDevices(duration = 3000): Promise<{
  devices: DiscoveredDevice[];
  interfaces: MdnsInterface[];
}> {
  // Joining every interface does not select the outgoing route. A wildcard
  // send can follow a VPN or virtual adapter even when the LAN is reachable.
  const addresses = new Set(Object.values(networkInterfaces()).flatMap((entries) =>
    (entries ?? []).filter((entry) => entry.family === "IPv4" && !entry.internal).map((entry) => entry.address),
  ));
  if (!addresses.size) addresses.add("127.0.0.1");

  const devices = new Map<string, DiscoveredDevice>();
  const interfaces = await Promise.all([...addresses].map(async (address): Promise<MdnsInterface> => {
    try {
      await browseInterface(address, duration, (device) => {
        const key = discoveredDeviceKey(device);
        if (!devices.has(key)) devices.set(key, device);
      });
      return { address };
    } catch (error) {
      const failure = error as NodeJS.ErrnoException | undefined;
      return { address, error: failure?.code ?? failure?.message ?? "Unknown mDNS error" };
    }
  }));
  return { devices: [...devices.values()], interfaces };
}

function browseInterface(address: string, duration: number, onDevice: (device: DiscoveredDevice) => void): Promise<void> {
  const bonjour = createBonjour(address);
  return new Promise<void>((resolve, reject) => {
    const browser = bonjour.find({ type: MDNS_SERVICE_TYPE.slice(1, -5) });
    let answered = false;
    const onService = (service: BonjourServiceRecord): void => {
      const device = parseService(service);
      if (device) {
        answered = true;
        onDevice(device);
      }
    };
    browser.on("up", onService);
    browser.on("txt-update", onService);

    let finished = false;
    const finish = (error?: Error): void => {
      if (finished) return;
      finished = true;
      clearTimeout(retry);
      clearTimeout(deadline);
      browser.stop();
      bonjour.destroy();
      if (error) reject(error);
      else resolve();
    };
    const retry = setTimeout(() => {
      if (!answered) {
        browser.mdns.query(`${MDNS_SERVICE_TYPE}.local`, "PTR", (error) => {
          if (error) finish(error);
        });
      }
    }, duration / 2);
    const deadline = setTimeout(finish, duration);
    browser.mdns.on("error", finish);
    browser.mdns.on("warning", (error) => {
      if (error.syscall === "addMembership" || error.syscall === "setMulticastInterface") {
        // The transport is still configuring the socket in its listening callback.
        queueMicrotask(() => { finish(error); });
      }
    });
  });
}

function createBonjour(address: string): BonjourClient {
  const module = bonjourService as unknown as BonjourModule;
  const Bonjour = typeof module === "function" ? module : module.Bonjour ?? module.default;
  if (!Bonjour) {
    throw new TypeError("bonjour-service did not expose a Bonjour constructor");
  }
  // Bind to all local addresses to receive multicast, but join and send on
  // this interface only. Binding to its unicast address can discard replies.
  return new Bonjour({ interface: address, bind: "0.0.0.0" });
}

/** Prefer IPv4, then global IPv6, then link-local IPv6 as last resort. */
function pickAddress(addresses: string[], fallback?: string): string | undefined {
  // When the sender is one of the advertised addresses, use the interface
  // that answered. Bonjour can include addresses from other links too.
  if (fallback && !fallback.includes(":") && addresses.includes(fallback)) return fallback;
  const all = fallback ? [...addresses, fallback] : addresses;
  const ipv4 = all.find((a) => !a.includes(":"));
  if (ipv4) return ipv4;
  const globalV6 = all.find((a) => a.includes(":") && !a.startsWith("fe80"));
  if (globalV6) return globalV6;
  return all[0];
}

function parseService(service: BonjourServiceRecord): DiscoveredDevice | null {
  const txt = service.txt;
  if (!txt?.id) return null;

  const ip = pickAddress(service.addresses ?? [], service.referer?.address);
  if (!ip) return null;

  return {
    id: txt.id,
    name: txt.name ?? service.name,
    ip,
    port: Number(txt.port) || service.port,
    platform: parsePlatform(txt.platform),
    runtimeMode: parseRuntimeMode(txt.runtime_mode),
    engine: txt.engine,
    model: txt.model ?? "Unknown",
    width: Number(txt.width) || 0,
    height: Number(txt.height) || 0,
    version: txt.version ?? "0.0.0",
    lastSeen: Date.now(),
  };
}
