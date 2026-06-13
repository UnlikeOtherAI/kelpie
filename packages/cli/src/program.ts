import { Command } from "commander";
import { DEFAULT_PORT } from "@unlikeotherai/kelpie-shared";
import { registerAllCommands } from "./commands/index.js";
import { deviceCommand } from "./commands/helpers.js";

function parseUrlArgument(value: string): URL | undefined {
  try {
    return new URL(value);
  } catch {
    return undefined;
  }
}

function isDirectUrlArgument(value: string): boolean {
  const parsed = parseUrlArgument(value);
  return parsed !== undefined && parsed.protocol.length > 1;
}

export function createProgram(version: string): Command {
  const program = new Command();

  program
    .name("kelpie")
    .description("LLM-first browser automation CLI for iOS and Android")
    .version(version)
    .option("--device <id|name|ip>", "Target a specific device by ID, name, or IP")
    .option("--tabId <id>", "Target a specific tab on macOS commands that support per-tab control")
    .option("--tab-id <id>", "Alias for --tabId")
    .option("--format <type>", "Output format: json, table, text", "json")
    .option("--timeout <ms>", "Command timeout in milliseconds", "10000")
    .option("--port <port>", "Override default port", String(DEFAULT_PORT))
    .option("--llm-help", "Show detailed LLM-oriented help with schemas and examples")
    .argument("[url]", "Compatibility shorthand for `navigate <url>`")
    .action(async (url?: string) => {
      if (!url) {
        program.help();
        return;
      }
      if (!isDirectUrlArgument(url)) {
        program.error(`unknown command '${url}'`);
      }
      await deviceCommand(program, "navigate", { url });
    });

  program.addHelpText("after", "\nFeedback: Report issues and unexpected automation failures at https://github.com/UnlikeOtherAI/kelpie/issues");

  registerAllCommands(program);
  return program;
}
