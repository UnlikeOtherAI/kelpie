# Kelpie — Project Guide

@./AGENTS.md

## What This Is

Kelpie is an LLM-first browser for iOS and Android that enables language models to control real mobile browsers on the local network via mDNS discovery, HTTP API, and MCP. A companion Node.js CLI orchestrates individual and group commands across multiple devices.

## Claude-Specific Notes

- Keep instructions modular and prefer progressive disclosure.
- If deeper scoped behavior is needed, use `.claude/rules/` files.
- Prefer single-responsibility functions. When touching a method that mixes multiple concerns, split it along readability and responsibility boundaries before adding more logic.

## macOS SwiftUI + WebView Hit Testing

Three mechanisms silently kill button clicks — see the CRITICAL rule in AGENTS.md. Short version: **any button in a window containing a WebView must be an AppKit-backed NSButton subclass**. SwiftUI `Button` + WebView first-responder = broken every time.

## Debugging Protocol

- **Always check logs first** before diving into source code. Check device HTTP server logs, mDNS advertisement logs, and CLI output before analyzing code.
- **Never manually fix state** — if the mDNS discovery, HTTP server, or MCP server is stuck, fix the code so it self-heals.
- **Kill stale Kelpie app instances before verification** when they could block ports, AppReveal, or input testing. Debug against one known app process, not a mixture of old and new sessions.

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

## Using Codex as an External Agent

When dispatching work to Codex (`timeout 1800 codex exec "<prompt>"`), minimize Claude token spend:

- **Launch with `run_in_background: true`** — you'll be notified on completion, no polling needed.
- **Do not read the full output** — Codex output can be 50K+ lines. Only read the tail (last 20-30 lines) to check final status.
- **Check if the process is still alive** with `wc -l` on the output file, not by reading content.
- **After completion**: check what files were created (`find native -type f | sort`), then build and test. Don't review Codex's intermediate reasoning.
- **If Codex times out** (exit 144): check created files — it usually finishes writing before the review pass that times out.
- **Token discipline**: Codex does the implementation, Claude does orchestration + verification. Don't duplicate work by reading files Codex already analyzed.

## Task Management

`steroids llm` — run for current task management instructions.
