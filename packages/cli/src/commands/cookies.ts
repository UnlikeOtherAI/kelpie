import type { Command } from "commander";
import { deviceCommand } from "./helpers.js";

export function registerCookies(program: Command): void {
  const cookies = program
    .command("cookies")
    .description("Manage cookies");

  cookies
    .command("list")
    .description("Get cookies for the current page")
    .option("--name <name>", "Filter by cookie name")
    .action(async (opts: { name?: string }) => {
      const body: Record<string, unknown> = {};
      if (opts.name) body.name = opts.name;
      await deviceCommand(program, "getCookies", body);
    });

  cookies
    .command("set <name> <value>")
    .description("Set a cookie")
    .option("--domain <domain>", "Cookie domain")
    .option("--path <path>", "Cookie path")
    .option("--secure", "Secure flag")
    .option("--http-only", "HttpOnly flag")
    .option("--same-site <val>", "SameSite: Lax, Strict, None")
    .action(async (name: string, value: string, opts: {
      domain?: string;
      path?: string;
      secure?: boolean;
      httpOnly?: boolean;
      sameSite?: string;
    }) => {
      const body: Record<string, unknown> = { name, value };
      if (opts.domain) body.domain = opts.domain;
      if (opts.path) body.path = opts.path;
      if (opts.secure) body.secure = true;
      if (opts.httpOnly) body.httpOnly = true;
      if (opts.sameSite) body.sameSite = opts.sameSite;
      await deviceCommand(program, "setCookie", body);
    });

  cookies
    .command("delete")
    .description("Delete cookies")
    .option("--name <name>", "Delete by name")
    .option("--domain <domain>", "Scope by domain")
    .option("--all", "Delete all cookies")
    .action(async (opts: { name?: string; domain?: string; all?: boolean }) => {
      const body: Record<string, unknown> = {};
      if (opts.name) body.name = opts.name;
      if (opts.domain) body.domain = opts.domain;
      if (opts.all) body.deleteAll = true;
      await deviceCommand(program, "deleteCookies", body);
    });
}
