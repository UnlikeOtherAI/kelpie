# macOS Gecko Bundled Runtime Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bundle a stripped Firefox runtime inside Kelpie.app so the Gecko renderer requires no external Firefox installation — identical to how `Chromium Embedded Framework.framework` is bundled for CEF.

**Architecture:** A download script fetches a pinned Firefox DMG, extracts the binary, strips Mozilla branding (bundle ID, display name, adds `LSUIElement` so it never appears in the Dock), and places the result as `apps/macos/Frameworks/KelpieGeckoHelper.app` (gitignored, same as the CEF framework). A `project.yml` post-build script copies it into the built app's `Contents/Frameworks/`. `GeckoProcessManager` prefers the bundled binary path over any system Firefox, falling back to system Firefox for developer convenience. Rendering stays headless + CDP screenshot-based (same as current); the win is no external dependency.

**Tech Stack:** bash (download script), Swift (`GeckoProcessManager`), xcodegen (`project.yml`), GNU Make

---

## Background

`apps/macos/Frameworks/` is gitignored. CEF is placed there during setup. Firefox will follow the same pattern:

- `scripts/download-gecko-runtime.sh` — download + strip + place
- `make gecko-runtime` — convenience target
- `project.yml` postBuildScript — copies into built `.app` bundle
- `GeckoProcessManager` — uses `Bundle.main` path first

Open-source project, MPL 2.0. No licensing issues. Don't use the "Firefox" name in UI — we already call it "gecko".

---

## Task 1: Download and strip script

**Files:**
- Create: `scripts/download-gecko-runtime.sh`

**Step 1: Create the script**

```bash
#!/usr/bin/env bash
# Downloads a pinned Firefox release, strips Mozilla branding, and places the
# result as apps/macos/Frameworks/KelpieGeckoHelper.app.
# Run once: make gecko-runtime
set -euo pipefail

FIREFOX_VERSION="122.0.1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="$SCRIPT_DIR/../apps/macos/Frameworks"
HELPER_APP="$DEST_DIR/KelpieGeckoHelper.app"
TMP_DMG="/tmp/kelpie-gecko-${FIREFOX_VERSION}.dmg"
MOUNT_POINT="/Volumes/KelpieFirefoxSetup"

if [ -d "$HELPER_APP" ]; then
  echo "KelpieGeckoHelper.app already present. Delete it to re-download."
  exit 0
fi

echo "→ Downloading Firefox ${FIREFOX_VERSION}..."
curl -L --progress-bar \
  "https://releases.mozilla.org/pub/firefox/releases/${FIREFOX_VERSION}/mac/en-US/Firefox%20${FIREFOX_VERSION}.dmg" \
  -o "$TMP_DMG"

echo "→ Mounting DMG..."
hdiutil attach "$TMP_DMG" -mountpoint "$MOUNT_POINT" -quiet -nobrowse

echo "→ Copying..."
cp -R "$MOUNT_POINT/Firefox.app" "$HELPER_APP"

echo "→ Unmounting..."
hdiutil detach "$MOUNT_POINT" -quiet
rm -f "$TMP_DMG"

echo "→ Stripping Mozilla branding..."
PLIST="$HELPER_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.kelpie.gecko-helper"  "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName KelpieGeckoHelper"               "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName KelpieGeckoHelper"        "$PLIST"
# Prevent the helper from appearing in the Dock or App Switcher
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true"                           "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :LSUIElement true"                           "$PLIST"

echo "→ Re-signing with ad-hoc identity..."
codesign --remove-signature "$HELPER_APP" 2>/dev/null || true
codesign -fs - "$HELPER_APP" 2>/dev/null || true

echo "✓ KelpieGeckoHelper.app ready at $HELPER_APP"
```

**Step 2: Make it executable**

```bash
chmod +x scripts/download-gecko-runtime.sh
```

**Step 3: Verify it runs (requires internet)**

```bash
bash scripts/download-gecko-runtime.sh
ls -la apps/macos/Frameworks/KelpieGeckoHelper.app/Contents/MacOS/firefox
```

Expected: file exists, is executable.

**Step 4: Verify branding is stripped**

```bash
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
  apps/macos/Frameworks/KelpieGeckoHelper.app/Contents/Info.plist
```

Expected: `com.kelpie.gecko-helper`

**Step 5: Commit**

```bash
git add scripts/download-gecko-runtime.sh
git commit -m "feat(macos): add gecko runtime download script"
```

---

## Task 2: Add `make gecko-runtime` target

**Files:**
- Modify: `Makefile` (root)

**Step 1: Add target after the `macos` block (around line 175)**

In the `# ── macOS ──` section, add after `macos-run:`:

```makefile
gecko-runtime:
	@echo "→ Downloading Gecko runtime..."
	bash scripts/download-gecko-runtime.sh
```

Also add `gecko-runtime` to the `.PHONY` list at the top of the Makefile, and add a help line:

```makefile
@echo "  make gecko-runtime          Download and bundle Gecko (Firefox) runtime"
```

**Step 2: Verify**

```bash
make gecko-runtime
```

Expected: either "already present" (if Task 1 ran) or downloads and places the app.

**Step 3: Commit**

```bash
git add Makefile
git commit -m "feat(macos): add make gecko-runtime target"
```

---

## Task 3: Embed Gecko helper in the built app bundle

**Files:**
- Modify: `apps/macos/project.yml`

**Step 1: Add postBuildScript to the `Kelpie` target**

In `project.yml`, the `Kelpie` target already has `postBuildScripts`. Add a new entry after the existing `Embed KelpieHelper` script:

```yaml
      - name: Embed Gecko Helper
        script: |
          GECKO_SRC="${PROJECT_DIR}/Frameworks/KelpieGeckoHelper.app"
          GECKO_DST="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/KelpieGeckoHelper.app"
          if [ -d "$GECKO_SRC" ]; then
            rm -rf "$GECKO_DST"
            cp -R "$GECKO_SRC" "$GECKO_DST"
            codesign -fs - "$GECKO_DST" 2>/dev/null || true
            echo "Gecko helper embedded at $GECKO_DST"
          else
            echo "warning: KelpieGeckoHelper.app not found in Frameworks/ — run 'make gecko-runtime' first"
          fi
        basedOnDependencyAnalysis: false
```

**Step 2: Regenerate Xcode project**

```bash
cd apps/macos && xcodegen generate --spec project.yml
```

Expected: `Created project at .../Kelpie.xcodeproj`

**Step 3: Verify build still passes**

```bash
cd apps/macos && xcodebuild -scheme Kelpie -configuration Debug build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

If Gecko runtime is present, also verify it ends up in the built app:

```bash
find apps/macos/.build -name "firefox" -path "*/KelpieGeckoHelper*" 2>/dev/null | head -3
```

Expected: path inside `Kelpie.app/Contents/Frameworks/KelpieGeckoHelper.app/`.

**Step 4: Commit**

```bash
git add apps/macos/project.yml apps/macos/Kelpie.xcodeproj/project.pbxproj
git commit -m "feat(macos): embed KelpieGeckoHelper.app in app bundle via postBuildScript"
```

---

## Task 4: Update GeckoProcessManager to use bundled binary

**Files:**
- Modify: `apps/macos/Kelpie/Renderer/GeckoProcessManager.swift`

**Step 1: Read the current file**

```
apps/macos/Kelpie/Renderer/GeckoProcessManager.swift
```

**Step 2: Replace `locateFirefox()` and add `bundledFirefoxPath()`**

Replace the existing `locateFirefox()` static method and `firefoxPaths` property with:

```swift
/// Path to the Firefox binary bundled inside Kelpie.app.
/// Returns nil if the Gecko runtime has not been downloaded yet.
static func bundledFirefoxPath() -> String? {
    // In the built app: Kelpie.app/Contents/Frameworks/KelpieGeckoHelper.app/Contents/MacOS/firefox
    guard let executableURL = Bundle.main.executableURL else { return nil }
    let path = executableURL
        .deletingLastPathComponent()           // Contents/MacOS
        .deletingLastPathComponent()           // Contents
        .appendingPathComponent("Frameworks/KelpieGeckoHelper.app/Contents/MacOS/firefox")
        .path
    return FileManager.default.isExecutableFile(atPath: path) ? path : nil
}

/// System Firefox paths checked as a developer fallback when the bundled
/// runtime is absent (e.g. during development before running make gecko-runtime).
static let systemFirefoxPaths: [String] = [
    "/Applications/Firefox.app/Contents/MacOS/firefox",
    "/Applications/Firefox Developer Edition.app/Contents/MacOS/firefox",
    (NSHomeDirectory() as NSString).appendingPathComponent(
        "Applications/Firefox.app/Contents/MacOS/firefox"
    ),
]

/// Returns the Firefox binary to use: bundled runtime first, system Firefox as fallback.
static func locateFirefox() -> String? {
    if let bundled = bundledFirefoxPath() { return bundled }
    return systemFirefoxPaths.first { FileManager.default.fileExists(atPath: $0) }
}
```

Also update `start()` to create the profile with privacy prefs. Replace the profile creation block (the lines that do `createDirectory`) with:

```swift
let tempProfile = FileManager.default.temporaryDirectory
    .appendingPathComponent("com.kelpie.gecko-profile-\(port)")
try? FileManager.default.createDirectory(at: tempProfile, withIntermediateDirectories: true)
profileDir = tempProfile
// Write profile prefs to suppress Firefox first-run UI and telemetry
writeProfilePrefs(to: tempProfile)
```

Add the `writeProfilePrefs` helper at the bottom of `GeckoProcessManager`:

```swift
private func writeProfilePrefs(to profileURL: URL) {
    let userJS = """
    user_pref("app.update.auto", false);
    user_pref("app.update.enabled", false);
    user_pref("browser.shell.checkDefaultBrowser", false);
    user_pref("browser.startup.firstrunSkipsHomepage", true);
    user_pref("browser.startup.homepage_override.mstone", "ignore");
    user_pref("datareporting.healthreport.uploadEnabled", false);
    user_pref("datareporting.policy.dataSubmissionEnabled", false);
    user_pref("toolkit.telemetry.enabled", false);
    user_pref("toolkit.telemetry.unified", false);
    """
    try? userJS.write(
        to: profileURL.appendingPathComponent("user.js"),
        atomically: true, encoding: .utf8
    )
}
```

**Step 3: Verify build**

```bash
cd apps/macos && xcodebuild -scheme Kelpie -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **` with no `error:` lines.

**Step 4: Commit**

```bash
git add apps/macos/Kelpie/Renderer/GeckoProcessManager.swift
git commit -m "feat(macos): GeckoProcessManager uses bundled Firefox runtime with privacy prefs"
```

---

## Task 5: Update docs

**Files:**
- Modify: `docs/tech-stack.md` — note Gecko runtime setup step
- Modify: `docs/functionality.md` — update Gecko rendering description
- Modify: `docs/plans/2026-04-01-macos-gecko-renderer.md` — mark superseded

**Step 1: Find and update the macOS setup section in `docs/tech-stack.md`**

Search for any "CEF" or "setup" section and add a note that `make gecko-runtime` must be run before building with Gecko support:

```markdown
**macOS Gecko runtime:** Run `make gecko-runtime` once to download and bundle
the Gecko (Firefox) runtime into `apps/macos/Frameworks/`. Required before the
Gecko renderer option works. The runtime is gitignored (same as CEF).
```

**Step 2: Update `docs/functionality.md` Renderer Switching section**

Find the Gecko paragraph added in the previous plan and update the line about "requires Firefox.app installed":

Before: `Firefox must be installed at a standard path...`
After: `The Gecko runtime is bundled inside Kelpie.app (run \`make gecko-runtime\` once during setup). No external Firefox installation required.`

**Step 3: Mark the old plan superseded**

Add one line at the top of `docs/plans/2026-04-01-macos-gecko-renderer.md` (after the `# ` heading):

```markdown
> **Superseded** by `docs/plans/2026-04-01-macos-gecko-bundled.md`. The subprocess approach is retained but the binary is now bundled — no external Firefox.app required.
```

**Step 4: Commit**

```bash
git add docs/tech-stack.md docs/functionality.md docs/plans/2026-04-01-macos-gecko-renderer.md
git commit -m "docs: update Gecko setup docs — bundled runtime, make gecko-runtime"
```

---

## Verification checklist (after all tasks complete)

1. `make gecko-runtime` → downloads, places, strips branding, no errors
2. `xcodebuild ... build` → `** BUILD SUCCEEDED **`
3. `find apps/macos/.build -name "firefox" -path "*/KelpieGeckoHelper*"` → file found inside built bundle
4. Launch app → switch to Gecko via `curl -X POST http://localhost:8420/v1/set-renderer -d '{"engine":"gecko"}'`
5. Response → `{"success":true,"engine":"gecko","changed":true}`
6. Navigate → `curl -X POST http://localhost:8420/v1/navigate -d '{"url":"https://example.com"}'`
7. `curl http://localhost:8420/v1/get-current-url` → `{"url":"https://example.com",...}`
8. No Firefox window appears in Dock or App Switcher
9. Delete `apps/macos/Frameworks/KelpieGeckoHelper.app`, re-run `make gecko-runtime`, repeat 2–8

---

## Known limitation

The live view in `GeckoLiveView` renders via CDP `Page.captureScreenshot` at ~5fps (screenshot polling). This gives real Firefox rendering in the Kelpie shell but with slight lag. Firefox's CDP does not expose `Page.startScreencast` (a Chrome-only extension). A higher-fidelity path using `ScreenCaptureKit` to capture the Firefox window directly can be added in a follow-up — it would require Screen Recording permission but deliver 60fps rendering.
