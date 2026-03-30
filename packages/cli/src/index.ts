#!/usr/bin/env node
import { Command } from "commander";
import { DEFAULT_PORT } from "@unlike-other-ai/mollotov-shared";
import { registerAllCommands } from "./commands/index.js";

const program = new Command();

program
  .name("mollotov")
  .description("LLM-first browser automation CLI for iOS and Android")
  .version("0.1.0")
  .option("--device <id|name|ip>", "Target a specific device by ID, name, or IP")
  .option("--format <type>", "Output format: json, table, text", "json")
  .option("--timeout <ms>", "Command timeout in milliseconds", "10000")
  .option("--port <port>", "Override default port", String(DEFAULT_PORT))
  .option("--llm-help", "Show detailed LLM-oriented help with schemas and examples");

registerAllCommands(program);

program.parseAsync(process.argv);
