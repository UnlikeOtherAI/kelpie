#!/usr/bin/env node
import { createRequire } from "module";
import { createProgram } from "./program.js";

const require = createRequire(import.meta.url);
const { version } = require("../package.json") as { version: string };

const program = createProgram(version);

// Handle --llm-help before commander parses
const llmHelpIdx = process.argv.indexOf("--llm-help");
if (llmHelpIdx !== -1) {
  const { generateLlmHelp } = await import("./help/llm-help.js");
  const commandArg = process.argv
    .slice(2, llmHelpIdx)
    .filter((arg) => !arg.startsWith("-"))
    .join(" ")
    .trim();
  console.log(generateLlmHelp(commandArg || undefined));
  process.exit(0);
}

void program.parseAsync(process.argv);
