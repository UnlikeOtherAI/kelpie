# Common base merge for parallel platform work

Integration source: 08d5e301b188590224672d8ad38c1777e83e8311.
Upstream main: 195eb90f (full parent recorded by the merge commit).
Owned branch/worktree: codex/capture-observations-20261104,
D:/Worktrees/kelpie/capture-observations-20261104.
Resource grant: COMMON-MERGE-8, one test worker/native compiler. Computer Use off.

## Conflict decisions

- docs/cli.md: retain favourites-tree MCP commands and external-worker MCP docs;
  keep favourites under browser control, then the external-worker section.
- docs/functionality.md: retain the full favourites tree/live-settings behavior,
  bounded observations, typed workflows and explicit external automation sessions.
- browser_contract.cmake: retain upstream recursive shared-source dependency scan;
  it includes browser-control, workflow, favourites, and partition sources.
- mcp_tool.cpp: retain three favourites descriptors and all-platform named-storage
  metadata from main plus four Windows Chromium workflow descriptors. Remove the
  obsolete desktop-only partition availability list.
- test_mcp_registry.cpp: exact combined counts are all128, iOS121, Android121,
  macOS118, Windows118, Linux114, WebKit124 and Chromium128; preserve new favourites,
  mobile partitions and Windows-only script assertions.
- extension-tools.ts: retain strict workflow/artifact schema imports and upstream
  isValidPartition/validatePartitionDeletion validation together.

The auto-merged generator retains fixed bounded observation sources, workflow and
target assets, host-only field stripping, request/script parity cases, and upstream
pattern-aware validated schema fixtures. Package versions and release changes from
main are retained; no additional component version bump is made by this merge.

Windows owner clarified that playback needs the native app renderer HWND and
presentation/Stop factory. Playback metadata is now UI-required and disallows pure
headless-backend execution; normal hidden app launch is separate. Status/artifact
reads and abort keep existing authenticated transport behavior. A focused registry
assertion guards this distinction. No other platform is admitted prematurely.

## Checks

Fresh preflight: Maxis CPU9%, free physical memory24,196,392KiB.
Task logs: D:/Temp/capture-observations-20261104/merge8-*.log.

- [x] pnpm.cmd install --frozen-lockfile --ignore-scripts.
- [x] pnpm.cmd lint; pnpm.cmd build.
- [x] pnpm.cmd --filter @unlikeotherai/kelpie-shared test --maxWorkers=1 --minWorkers=1:
  128 tests passed.
- [x] pnpm.cmd --filter @unlikeotherai/kelpie exec vitest run tests/mcp/tools.test.ts
  tests/mcp/script-admission.test.ts tests/mcp/script-secrets.test.ts
  tests/commands/partitions.test.ts tests/help/docs-drift.test.ts
  --maxWorkers=1 --minWorkers=1: 230 focused tests passed.
- [x] cmake --build D:/BuildArtifacts/kelpie/capture-observations-20261104/native
  --config Release --target test_mcp_registry test_native_extensions
  test_browser_gateway --parallel 1.
- [x] ctest --test-dir D:/BuildArtifacts/kelpie/capture-observations-20261104/native
  -C Release -R "test_mcp_registry|test_native_extensions|test_browser_gateway"
  --output-on-failure: 3/3 passed, 5.08 seconds. Existing NDEBUG/UNDEBUG
  test-option warnings remain.

No browser, application, inference runtime, native UI, or release acceptance was
run by this merge check. Full integrated feature checks and each platform's actual
machine-flow evidence still gate final delivery. Upstream main release evidence is
not silently substituted for new workflow evidence.

The pending metadata-index/:scope follow-up is not part of the merge. It remains
preserved in stash195462d7011e4c5d739a02e1d753c7d08ccb1137, with earlier redundant
backup2286bfa7b47f81c7eb9e932fd6cd2d5a48381164 retained until safely reconciled.
