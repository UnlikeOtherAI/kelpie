# Kelpie — Agent Guide

> Read CLAUDE.md and AGENTS.md before starting any work. Update both when policy changes.

## Source of Truth

**Static docs — read these to understand the project:**
- Product brief: [docs/brief.md](docs/brief.md) — what, why, how, MVP scope
- System architecture: [docs/architecture.md](docs/architecture.md) — components, data flow, protocols
- Tech stack: [docs/tech-stack.md](docs/tech-stack.md) — platform choices, dependencies, repo structure
- Feature catalogue: [docs/functionality.md](docs/functionality.md) — description of every user-facing feature
- API reference: [docs/api/](docs/api/) — all HTTP/MCP methods (core, LLM-optimized, devtools, browser management)
- CLI reference: [docs/cli.md](docs/cli.md) — commands, flags, group operations, LLM help system
- UI documentation: [docs/ui/](docs/ui/) — browser app screens, settings panel, platform specifics

**Evolving docs — created as needed when work begins (do not auto-load):**
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

## Platform Parity (CRITICAL)

iOS and Android must be kept as absolute mirrors with full feature parity. Every feature, UI element, and behavior implemented on one platform must be implemented identically on the other in the same commit or PR.

## Code Rules

- 500-line file limit — split along responsibility seams, not arbitrarily. Never trim comments or blank lines to fit.
- Documentation: 1,000-line limit — exceeding requires a dedicated folder with README.md linking sub-files.
- No persistent content scripts — interaction via native WebView APIs and CDP. Some iOS features use ephemeral bridge scripts (see architecture.md).
- All browser-CLI communication over HTTP/JSON with `/v1/` prefix.
- MCP tools use `kelpie_` prefix.
- mDNS service type: `_kelpie._tcp`.
- Default port: `8420`.
- Package manager: pnpm.
- CLI: TypeScript, native apps: Swift (iOS) / Kotlin (Android).
- npm scope: `@unlikeotherai/kelpie`.

## Agent Behavior Rules

### Root-Cause First (CRITICAL)

Do not patch around a failure before understanding the defect. Diagnose and document the root cause first; fix the broken invariant directly.

### Simplification First (CRITICAL)

Before patching, ask whether the right fix is to simplify. Every change must reduce or hold total system complexity — never increase it.

### No Keychain (CRITICAL)

Never use the macOS Keychain for storage. Use UserDefaults or file-based storage. CEF must use `--use-mock-keychain` to avoid Chromium Safe Storage prompts.

### No Manual Recovery (CRITICAL)

Never manually fix state to work around a bug. Fix the code so the system self-heals.

### Kill Stale Browser Instances (CRITICAL)

During debugging or verification, always terminate any existing Kelpie browser app instance that could block ports, AppReveal, or interaction testing before launching the build you intend to test. Do not work around stale processes by guessing which instance responded — ensure there is one known-good target.

### Documentation Alignment (CRITICAL)

Feature work is incomplete until docs are updated. When adding or changing API endpoints, CLI commands, or MCP tools, update the relevant docs in the same commit. Every user-facing feature must be described in [docs/functionality.md](docs/functionality.md) — update it when adding or changing features.

### macOS: SwiftUI Buttons in WebView Windows (CRITICAL)

Three distinct mechanisms can silently kill SwiftUI button clicks. All three have hit this codebase.

**1 — WebView first-responder steals mouseDown (the hardest to debug)**
Once WKWebView or CEF becomes first responder, macOS dispatches all subsequent `mouseDown` events through the AppKit responder chain starting at the WebView. SwiftUI `Button` views live in NSHostingView's gesture layer and lose the race — they never receive the event. `.contentShape(Rectangle())` does NOT fix this.

**Rule: Every toolbar/UI control in a window that contains a WebView MUST be an AppKit-backed `NSButton` subclass via NSViewRepresentable.** AppKit resolves these at the `hitTest` level before the responder chain runs, so WebView focus cannot block them. Follow the `AppKitToolbarButton` / `AppKitSegmentedStrip` pattern in `URLBarView.swift`. Never add a new SwiftUI `Button` to the URL bar or any chrome area adjacent to the renderer.

**2 — Full-window NSViewRepresentable overlays block SwiftUI gestures**
SwiftUI's gesture pipeline does not forward `mouseDown` through NSViewRepresentable views even when the underlying NSView returns `nil` from `hitTest`. A full-window overlay kills every SwiftUI control behind it.

**Rule:** Scope NSViewRepresentable overlays to the smallest possible area. `FloatingMenuView` is scoped to the renderer ZStack only — not the full window. Never use `.frame(maxWidth: .infinity, maxHeight: .infinity)` on an NSViewRepresentable that sits above SwiftUI buttons.

**3 — `.buttonStyle(.plain)` hit areas are label-only**
`.frame()`, `.padding()`, `.background()`, and `.contentShape()` on the Button wrapper do not expand the clickable area — only what is inside the `label:` closure counts.

**Rule:** Put all visual modifiers inside the `label:` closure and end with `.contentShape(Rectangle())`. The Button wrapper should only carry `.buttonStyle(.plain)`, `.disabled()`, and `.accessibilityIdentifier()`.

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
- macOS: After every change, rebuild and launch the app to verify. Kill any stale instance first, then keep the new one running until the next build replaces it.

## Versioning

Each component owns its version in its own manifest — do not create a central version file:

| Component | Version location |
|-----------|-----------------|
| macOS app | `apps/macos/Kelpie/Info.plist` → `CFBundleShortVersionString` |
| iOS app   | `apps/ios/Kelpie.xcodeproj/project.pbxproj` → `MARKETING_VERSION` |
| Android   | `apps/android/app/build.gradle.kts` → `versionName` |
| CLI       | `packages/cli/package.json` → `version` |

- Bump only the component(s) being released — other components stay at their current version.
- GitHub releases use a date tag (`release/YYYY-MM-DD`). The tag description must list every component version included in that release.

## Commits

- Small, focused commits — one concern per commit
- Push after each meaningful change
