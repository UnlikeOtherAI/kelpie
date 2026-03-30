# Mollotov — Agent Guide

> Read CLAUDE.md and AGENTS.md before starting any work. Update both when policy changes.

## Source of Truth

**Static docs — read these to understand the project:**
- Product brief: [docs/brief.md](docs/brief.md) — what, why, how, MVP scope
- System architecture: [docs/architecture.md](docs/architecture.md) — components, data flow, protocols
- Tech stack: [docs/tech-stack.md](docs/tech-stack.md) — platform choices, dependencies, repo structure
- API reference: [docs/api/](docs/api/) — all HTTP/MCP methods (core, LLM-optimized, devtools, browser management)
- CLI reference: [docs/cli.md](docs/cli.md) — commands, flags, group operations, LLM help system
- UI documentation: [docs/ui/](docs/ui/) — browser app screens, settings panel, platform specifics

**Evolving docs — check when working on tasks (do not auto-load):**
- Design plans: `docs/plans/` (active) / `docs/done/` (completed)
- Feature specs: `docs/specs/`
- Task breakdowns: `docs/to-do/`

## Cross-Provider Reviews

Get a second opinion from a different provider **before implementation** for: new features spanning 3+ files, architectural changes, design documents, changes to the HTTP/MCP protocol or mDNS discovery.

### How to Conduct a Review

1. Write the design/spec first — complete thinking before seeking review.
2. Send to a different provider. Instruct the reviewer to be **adversarial**: look for technical debt, architectural regression, type safety gaps, and logic holes.
3. The review is advisory. Assess each finding independently. Push back if the reviewer is wrong. Do not over-engineer.
4. Append a "Cross-Provider Review" section to the design doc.

**Skip review for:** typo fixes, doc-only updates, single-file changes under 50 lines.

## Code Rules

- 500-line file limit — split along responsibility seams, not arbitrarily. Never trim comments or blank lines to fit.
- Documentation: 1,000-line limit — exceeding requires a dedicated folder with README.md linking sub-files.
- No JS injection into web pages — all interaction via native WebView APIs or CDP.
- All browser-CLI communication over HTTP/JSON with `/v1/` prefix.
- MCP tools use `mollotov_` prefix.
- mDNS service type: `_mollotov._tcp`.
- Default port: `8420`.
- Package manager: pnpm.
- CLI: TypeScript, native apps: Swift (iOS) / Kotlin (Android).
- npm scope: `@unlike-other-ai/mollotov`.

## Agent Behavior Rules

### Root-Cause First (CRITICAL)

Do not patch around a failure before understanding the defect. Diagnose and document the root cause first; fix the broken invariant directly.

### Simplification First (CRITICAL)

Before patching, ask whether the right fix is to simplify. Every change must reduce or hold total system complexity — never increase it.

### No Manual Recovery (CRITICAL)

Never manually fix state to work around a bug. Fix the code so the system self-heals.

### Documentation Alignment (CRITICAL)

Feature work is incomplete until docs are updated. When adding or changing API endpoints, CLI commands, or MCP tools, update the relevant docs in the same commit.

### Architecture and Quality

- Prefer single-responsibility functions. When touching a method that mixes responsibilities, split it before adding more logic.
- Include targeted tests for bug fixes and new logic.
- Keep work in small isolated commits and push promptly.

### What Belongs in the Repo (CRITICAL)

Only commit permanent, hand-authored files. If it can be regenerated, do not commit it.

**Never commit:** build output (`dist/`, `*.tsbuildinfo`), one-off scripts, backup files, temporary notes.

**Always commit:** source, config, AI config (`CLAUDE.md`, `AGENTS.md`), migrations, permanent docs.

## Verification

- CLI: `pnpm build && pnpm test` must pass before committing
- iOS: Xcode build succeeds, no warnings
- Android: `./gradlew build` succeeds

## Commits

- Small, focused commits — one concern per commit
- Push after each meaningful change
