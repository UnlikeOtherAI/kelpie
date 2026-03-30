# Mollotov — Project Guide

@./AGENTS.md

## What This Is

Mollotov is an LLM-first browser for iOS and Android that enables language models to control real mobile browsers on the local network via mDNS discovery, HTTP API, and MCP. A companion Node.js CLI orchestrates individual and group commands across multiple devices.

## Claude-Specific Notes

- Keep instructions modular and prefer progressive disclosure.
- If deeper scoped behavior is needed, use `.claude/rules/` files.
- Prefer single-responsibility functions. When touching a method that mixes multiple concerns, split it along readability and responsibility boundaries before adding more logic.

## Debugging Protocol

- **Always check logs first** before diving into source code. Check device HTTP server logs, mDNS advertisement logs, and CLI output before analyzing code.
- **Never manually fix state** — if the mDNS discovery, HTTP server, or MCP server is stuck, fix the code so it self-heals.

## How to Run Parallel Adversarial Reviews

When a design requires cross-provider review, dispatch two reviewers **simultaneously** by sending a single message with two tool calls.

**Call 1 — Claude reviewer:**
```
Agent tool:
  subagent_type: superpowers:code-reviewer
  prompt: "Adversarial review of [content]. Be harsh. Do not suggest over-engineering."
```

**Call 2 — Codex reviewer:**
```
Bash tool:
  timeout 1800 codex exec "[adversarial review prompt]"
```

Both calls go in a **single message** so they execute in parallel.

## Task Management

`steroids llm` — run for current task management instructions.
