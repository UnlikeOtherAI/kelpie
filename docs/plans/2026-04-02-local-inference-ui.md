# Local Inference — UI Design

Companion to [2026-04-02-local-inference.md](2026-04-02-local-inference.md). This document covers the visual interface for AI model management across all platforms.

---

## Prerequisite: Hardware Info

`DeviceInfo` currently lacks RAM, CPU, and disk space. All platforms must add:

```
system:
  totalMemoryMB: 16384          # Total physical RAM
  availableMemoryMB: 9200       # RAM currently free
  diskFreeGB: 87.3              # Free storage on the data volume
  chipset: "Apple M2"           # CPU/chip name (best-effort)
```

**How to read on each platform:**

| Field | macOS | iOS | Android |
|---|---|---|---|
| totalMemoryMB | `ProcessInfo.processInfo.physicalMemory` | `ProcessInfo.processInfo.physicalMemory` | `ActivityManager.MemoryInfo.totalMem` |
| availableMemoryMB | `ProcessInfo` + `host_statistics64` | `os_proc_available_memory()` | `ActivityManager.MemoryInfo.availMem` |
| diskFreeGB | `FileManager.attributesOfFileSystem` | `FileManager.attributesOfFileSystem` | `StatFs(dataDir)` |
| chipset | `sysctl("machdep.cpu.brand_string")` | Model identifier lookup table | `Build.SOC_MODEL` (API 31+) or `/proc/cpuinfo` |

Linux and Windows already report memory. Add `diskFreeGB` and `chipset` to them too.

---

## Icons

### Font Awesome Solid (all platforms)

**Font file:** `FontAwesome6Free-Solid-900.otf` (bundled in each app's resources)

| Icon | Codepoint | Usage |
|---|---|---|
| `fa-eye` | U+F06E | Vision-capable model |
| `fa-eye-slash` | U+F070 | Text-only model |
| `fa-cloud-arrow-down` | U+F0ED | Download available |
| `fa-circle-check` | U+F058 | Downloaded / ready |
| `fa-spinner` | U+F110 | Downloading (animated rotation) |
| `fa-trash-can` | U+F2ED | Delete model |
| `fa-brain` | U+F5DC | AI pill in URL bar, opens chat panel |
| `fa-circle-exclamation` | U+F06A | Warning (model too large for device) |
| `fa-server` | U+F233 | Ollama backend indicator |
| `fa-microphone` | U+F130 | Voice input button in chat |
| `fa-thumbtack` | U+F08D | Pin/unpin chat panel (macOS) |

### Platform integration

- **macOS:** Extend `FontAwesome.swift` — add Solid font alongside existing Brands font. Register both in `registerFonts()`. Add icon constants to the enum.
- **iOS:** Bundle `FontAwesome6Free-Solid-900.otf`, register via `Info.plist` `UIAppFonts`. Create `FontAwesome.swift` mirroring macOS pattern.
- **Android:** Bundle the `.otf` in `assets/fonts/`. Load via `FontFamily(Font(R.font.fontawesome6_free_solid_900))` in Compose.

---

## Model Card Design

Every model in the list is rendered as a card. The card adapts to the model's state and the device's hardware.

### Card anatomy

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  [eye]  Gemma 4 E2B                        Q4   │
│                                                  │
│  Multimodal model by Google. Understands text    │
│  and images — can describe screenshots, read     │
│  page layouts, and extract visual information.   │
│  Good balance of speed and quality.              │
│                                                  │
│  2.5 GB download  •  ~3.8 GB RAM when loaded     │
│                                                  │
│  ┌──────────────────────────────────────────┐    │
│  │  [cloud-arrow-down]  Download            │    │
│  └──────────────────────────────────────────┘    │
│                                                  │
└──────────────────────────────────────────────────┘
```

### Card states

**Available — not downloaded:**

```
┌──────────────────────────────────────────────────┐
│  [eye]  Gemma 4 E2B                        Q4   │
│                                                  │
│  Multimodal model by Google. Understands text    │
│  and images — can describe screenshots, read     │
│  page layouts, and extract visual information.   │
│                                                  │
│  2.5 GB download  •  ~3.8 GB RAM when loaded     │
│                                                  │
│  [cloud-arrow-down]  Download                    │
└──────────────────────────────────────────────────┘
```

**Downloading:**

```
┌──────────────────────────────────────────────────┐
│  [eye]  Gemma 4 E2B                        Q4   │
│                                                  │
│  Multimodal model by Google. Understands text    │
│  and images — ...                                │
│                                                  │
│  ████████████░░░░░░░░░░░░  1.2 / 2.5 GB  48%    │
│                                                  │
│  [cancel]  Cancel                                │
└──────────────────────────────────────────────────┘
```

**Downloaded — not loaded:**

```
┌──────────────────────────────────────────────────┐
│  [eye]  Gemma 4 E2B                  Q4  [check] │
│                                                  │
│  Multimodal model by Google. Understands text    │
│  and images — ...                                │
│                                                  │
│  2.5 GB on disk  •  ~3.8 GB RAM when loaded      │
│                                                  │
│  [▶ Load]                          [trash] Delete│
└──────────────────────────────────────────────────┘
```

**Loaded — active:**

```
┌──────────────────────────────────────────────────┐
│  [eye]  Gemma 4 E2B              Q4  ● Active    │
│                                                  │
│  Multimodal model by Google. Understands text    │
│  and images — ...                                │
│                                                  │
│  Using 3.8 GB RAM                                │
│                                                  │
│  [⏹ Unload]                                      │
└──────────────────────────────────────────────────┘
```

**Warning — insufficient resources:**

```
┌──────────────────────────────────────────────────┐
│  [eye]  Gemma 4 E2B Q8                     Q8   │
│                                                  │
│  Higher quality variant. Needs 16 GB RAM.        │
│                                                  │
│  5.0 GB download  •  ~8 GB RAM when loaded       │
│                                                  │
│  [!] Not recommended for this device             │
│      Requires ~8 GB free RAM — you have 4.2 GB   │
│                                                  │
│  [cloud-arrow-down]  Download anyway             │
└──────────────────────────────────────────────────┘
```

**Insufficient storage:**

```
│  [!] Not enough storage                          │
│      Needs 5.0 GB — you have 2.1 GB free         │
│                                                  │
│  [cloud-arrow-down greyed]  Download  (disabled) │
```

---

## Hardware Evaluation Logic

### Model fitness scoring

Each model declares its requirements. The device reports its capabilities. The UI evaluates fitness at display time.

```ts
interface ModelRequirements {
  downloadSizeGB: number;          // Disk needed for download
  ramWhenLoadedGB: number;         // RAM consumed when model is active
  minRamGB: number;                // Minimum total device RAM
  recommendedRamGB: number;        // Comfortable total device RAM
  supportsMetalGPU?: boolean;      // Needs Metal (Apple) or Vulkan (Android)
}

interface DeviceCapabilities {
  totalRamGB: number;
  availableRamGB: number;
  diskFreeGB: number;
  chipset: string;
  platform: "macos" | "ios" | "android" | "linux" | "windows";
}
```

### Fitness levels

| Level | Condition | UI Treatment |
|---|---|---|
| **recommended** | `totalRam >= recommendedRam` AND `diskFree >= downloadSize * 1.2` | Normal card, download button prominent |
| **possible** | `totalRam >= minRam` AND `diskFree >= downloadSize` | Card shown with amber note: "May run slowly on this device" |
| **not-recommended** | `totalRam < minRam` | Card shown with warning: "Not recommended — requires X GB RAM, you have Y GB". Download button says "Download anyway" |
| **no-storage** | `diskFree < downloadSize` | Card greyed, download disabled: "Not enough storage — needs X GB, you have Y GB free" |

### Ollama models

Ollama models running on the same Mac need no fitness check — Ollama manages its own memory. Ollama models accessed remotely from mobile don't consume device resources at all. Show them with a `[server]` badge and no resource warnings.

### Platform AI models (Apple Intelligence / Gemini Nano)

No resource check needed — the OS manages these. Show them with an "On-device" badge. If the device doesn't support them (too old, wrong chip), show: "Requires [A17 Pro / Pixel 8+] — not available on this device" and disable.

### Sorting

Models are sorted within each section by fitness, then by size:

1. Recommended models, smallest first
2. Possible models, smallest first
3. Not-recommended models (shown at bottom, dimmed)

---

## Model Descriptions

Every model in the approved registry needs a human-readable description written for users who don't know what an LLM is. No jargon. Focus on what it can do, not how it works.

### Required description fields

```ts
interface ModelDescription {
  summary: string;            // 1 sentence: what does this model do?
  strengths: string[];        // 2-3 bullet points: what it's good at
  limitations: string[];      // 1-2 bullet points: what it can't do
  bestFor: string;            // "Best for: ___" one-liner
  speedRating: "fast" | "moderate" | "slow";  // Relative to other models in the list
}
```

### Example descriptions

**Gemma 4 E2B Q4:**
```
summary: "Understands text and images — can describe screenshots, read page layouts, and extract visual information."
strengths:
  - "Describe what's on a webpage from a screenshot"
  - "Summarise articles and extract key information"
  - "Answer questions about page content and structure"
limitations:
  - "Slower than text-only models when processing images"
  - "May struggle with very long pages (over 10,000 words)"
bestFor: "General page analysis with visual understanding"
speedRating: "moderate"
```

**Gemma 4 E2B Q8:**
```
summary: "Higher quality version of Gemma 4 — more accurate but needs more memory."
strengths:
  - "More accurate responses than Q4, especially for nuanced questions"
  - "Better at understanding complex page layouts"
  - "Same vision and text capabilities as Q4"
limitations:
  - "Needs 16 GB RAM — won't run comfortably on 8 GB machines"
  - "Slightly slower than Q4 due to larger model size"
bestFor: "When accuracy matters more than speed"
speedRating: "moderate"
```

**Ollama model (generic, auto-generated from Ollama metadata):**
```
summary: "Installed via Ollama. Managed externally — Mollotov can use it but doesn't download or delete it."
strengths: [derived from model capabilities if known]
limitations: ["Requires Ollama to be running"]
bestFor: "Use your existing Ollama models without re-downloading"
speedRating: [not shown — varies by model]
```

**Apple Intelligence:**
```
summary: "Apple's built-in on-device model. Fast and private — runs entirely on your device's neural engine."
strengths:
  - "Instant startup — no download needed"
  - "Very fast inference using the Neural Engine"
  - "Zero memory overhead — managed by the OS"
limitations:
  - "Text only — cannot analyse screenshots or images"
  - "Cannot be customised or replaced"
bestFor: "Quick text summaries when you don't need vision"
speedRating: "fast"
```

---

## CLI Output

### `mollotov ai list`

```
AI Models

  Recommended for this device (Apple M2, 16 GB RAM, 87 GB free)

  NATIVE
  ────────────────────────────────────────────────────────────
  👁  gemma-4-e2b-q4      2.5 GB    ~3.8 GB RAM    ✓ downloaded
     Understands text and images — page analysis with visual understanding
     [moderate speed]

  👁  gemma-4-e2b-q8      5.0 GB    ~8 GB RAM      not downloaded
     Higher quality Gemma 4 — more accurate but needs more memory
     [moderate speed]

  OLLAMA (localhost:11434 ● online)
  ────────────────────────────────────────────────────────────
  👁  ollama:llava:7b      4.7 GB    managed by Ollama
     Vision model — can describe images and screenshots

  ⊘  ollama:llama3.2:3b   2.0 GB    managed by Ollama
     Text-only general purpose model

  ⊘  ollama:gemma2:2b     1.6 GB    managed by Ollama
     Text-only, lightweight and fast

  PLATFORM
  ────────────────────────────────────────────────────────────
  ⊘  platform:apple       on-device  managed by OS
     Apple Intelligence — fast text summaries, no vision
```

### `mollotov ai list` on a constrained device (8 GB)

```
  AI Models

  Device: MacBook Air M1, 8 GB RAM, 34 GB free

  NATIVE
  ────────────────────────────────────────────────────────────
  👁  gemma-4-e2b-q4      2.5 GB    ~3.8 GB RAM    not downloaded
     Understands text and images — page analysis with visual understanding
     ⚠ May run slowly — leaves only ~4.2 GB for other apps

  👁  gemma-4-e2b-q8      5.0 GB    ~8 GB RAM      not downloaded
     Higher quality Gemma 4 — more accurate but needs more memory
     ✗ Not recommended — needs ~8 GB RAM, you have 8 GB total
```

### `mollotov ai status --device mac`

```
  Device: Mac Studio (Apple M2 Ultra, 64 GB RAM)
  Model:  gemma-4-e2b-q4 (native)
  Status: ● Loaded
  Vision: 👁 yes
  RAM:    3.8 GB used
  Uptime: 12m 34s
```

---

## macOS Settings — AI Section

The Settings panel keeps a compact AI section for quick model selection. The full chat and model browsing experience lives in the side panel (see below). Settings is for configuration, not interaction.

```
┌──────────────────────────────────────────────────────────────┐
│  Settings                                         [Done]     │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  Device                                                      │
│  Name         Mac Studio                                     │
│  Model        Mac14,13                                       │
│  ...                                                         │
│                                                              │
│  Renderer                                                    │
│  Active       WebKit                                         │
│  Available    webkit, chromium                                │
│                                                              │
│  AI                                                          │
│  Active Model    Gemma 4 E2B Q4                       [▾]    │
│  Device: Apple M2, 16 GB RAM, 87 GB free                     │
│  Ollama          http://localhost:11434       [Test] ● Online │
│                                                              │
│  Models run locally. No data leaves your device.             │
│                                                              │
│  Network                                                     │
│  ...                                                         │
└──────────────────────────────────────────────────────────────┘
```

The model picker dropdown shows the same condensed list (Native / Ollama / On-Device sections). Downloading, fitness scoring, and model cards are in the side panel's Models tab.

---

## iOS / Android Settings — AI Section

Same compact approach as macOS settings.

### iOS

```
┌──────────────────────────────────────────────────┐
│  Settings                              [Done]     │
├──────────────────────────────────────────────────┤
│                                                  │
│  AI                                              │
│  ──────────────────────────────────────────────  │
│  Active Model              Gemma 4 E2B Q4     >  │
│  Ollama Endpoint           Not configured     >  │
│                                                  │
│  Device: iPhone 15 Pro, 8 GB RAM, 34 GB free     │
│  ──────────────────────────────────────────────  │
└──────────────────────────────────────────────────┘
```

Tapping "Active Model" navigates to the AI chat screen's Models tab. Tapping "Ollama Endpoint" pushes to the Ollama config screen (URL field, test connection button).

### Android

Identical structure, Material 3 components.

---

## AI Chat Panel (macOS)

The primary AI interaction on macOS is a **side panel** attached to the browser window. Not a popover, not a modal — a persistent chat panel.

### Opening the panel

**Tap the brain pill** in the URL bar → toggles the side panel open/closed.

```
Brain pill in URL bar (model loaded):
← → ↻ [ https://example.com ] [🧠 👁 Gemma 4 Q4] [iPhone 15 ▾] [⬜▬] [Safari Chrome] [−100%+]

Brain pill (no model):
← → ↻ [ https://example.com ] [🧠] [iPhone 15 ▾] [⬜▬] [Safari Chrome] [−100%+]
```

### Panel layout

250px wide. Right edge of the browser window. Two tabs at the top, chat input at the bottom.

```
┌────────────────────────────────────────────────┬─────────────────────────────┐
│                                                │ [Chat]  [Models]       [📌] │
│                                                ├─────────────────────────────┤
│                                                │                             │
│                                                │  🧠 Gemma 4 E2B Q4          │
│                                                │  What are the prices on     │
│  Browser viewport                              │  this page?                 │
│  (shrinks by 250px when panel is pinned)       │                             │
│                                                │  ─────────────────────────  │
│                                                │                             │
│                                                │  The page shows three tiers:│
│                                                │  • Basic: $9/mo             │
│                                                │  • Pro: $29/mo              │
│                                                │  • Enterprise: $99/mo       │
│                                                │                             │
│                                                │                             │
│                                                │                             │
│                                                ├─────────────────────────────┤
│                                                │  [Type a question...   ] 🎤 │
└────────────────────────────────────────────────┴─────────────────────────────┘
```

### Tab 1: Chat

Scrollable conversation view. User messages right-aligned, assistant messages left-aligned. Chat input fixed at the bottom: text field + microphone button.

**Speech button (🎤):** Tap to start voice recording. Mic pulses red, countdown bar appears inside the input area (decreasing over 30 seconds). Tap again to stop early. If model has `audio` capability, raw audio goes to the model. If not, platform STT transcribes first.

**Conversation behavior depends on the model:**
- Native GGUF (`memory: false`): Each message is standalone. No history is sent. The chat view shows prior Q&A for reference, but the model doesn't see them.
- Ollama (`memory: true`): Sliding window of last 10 exchanges sent via `/api/chat`. Real multi-turn conversation.

**Page navigation resets the conversation** for both model types. When the URL changes, the chat clears.

### Tab 2: Models

Full model card list with download, load, unload. Same card design as the Model Card section above. Users can manage everything without opening Settings.

```
┌────────────────────────────────────────────────┬─────────────────────────────┐
│                                                │ [Chat]  [Models]       [📌] │
│                                                ├─────────────────────────────┤
│                                                │                             │
│                                                │  NATIVE                     │
│                                                │  ┌─────────────────────────┐│
│  Browser viewport                              │  │ 👁 Gemma 4 E2B Q4      ││
│                                                │  │ Text+Vision+Audio       ││
│                                                │  │ 2.5 GB • ● Active      ││
│                                                │  │           [⏹ Unload]   ││
│                                                │  └─────────────────────────┘│
│                                                │  ┌─────────────────────────┐│
│                                                │  │ 👁 Gemma 4 E2B Q8      ││
│                                                │  │ Text+Vision+Audio       ││
│                                                │  │ 5.0 GB  [↓ Download]   ││
│                                                │  └─────────────────────────┘│
│                                                │                             │
│                                                │  OLLAMA (● online)          │
│                                                │  ┌─────────────────────────┐│
│                                                │  │ 👁 llava:7b             ││
│                                                │  │ Text+Vision             ││
│                                                │  │        [▶ Load]        ││
│                                                │  └─────────────────────────┘│
│                                                │                             │
└────────────────────────────────────────────────┴─────────────────────────────┘
```

### Pin / Unpin

Pin icon (`fa-thumbtack`) in the top-right corner of the tab bar. **Pinned by default** — panel lives inside the browser window, viewport shrinks by 250px.

**Unpinning** detaches the panel into a separate `NSWindow`. The chat becomes a floating window that can be moved anywhere, including to another screen. But it's **bound to the parent browser window** — they're a pair:
- Closing the browser window closes the chat window
- Minimizing the browser minimizes the chat
- The chat window title includes the browser window identifier

**Magnetic docking:** When the user drags the detached chat window close to the right edge of its parent browser window (within ~20px), the chat snaps back into the browser as a pinned panel. While dragging, a subtle highlight appears on the browser's right edge to show the docking zone. Once docked, both windows move together as one.

**Each browser window gets its own chat instance.** Opening a second browser window creates a second independent chat. If unpinned, it's a separate floating window bound to the second browser window.

**Re-pinning** (clicking the pin icon in a detached window, or magnetic docking) snaps the floating window back into the browser as a side panel.

| State | Panel location | Viewport | Behavior |
|---|---|---|---|
| Pinned (default) | Inside browser window, right edge | Shrinks by 250px | Moves with browser |
| Unpinned | Separate `NSWindow`, freely movable | Full width restored | Bound to parent — close/minimize together, magnetic re-dock |
| Closed | Hidden | Full width | Brain pill toggles it back |

### Brain pill states (macOS)

| State | Visual | Tap action |
|---|---|---|
| No model loaded | `[🧠]` (dimmed) | Opens panel on Models tab |
| Model loaded, panel closed | `[🧠 👁 Gemma 4 Q4]` | Opens panel on Chat tab |
| Model loaded, panel open | `[🧠 👁 Gemma 4 Q4]` (highlighted) | Closes panel |

---

## AI Chat Screen (iOS / Android)

On mobile, tapping the brain pill navigates to a **full-screen chat view**. Same two-tab structure as macOS, filling the screen instead of a side panel.

### Opening

**Tap brain pill in URL bar** → pushes a new screen (iOS: `NavigationLink`, Android: nav component).

**Back button** → returns to the browser. Chat state persists until page navigation.

**Brain pill in floating menu** → same behavior as the URL bar pill.

### Layout

```
┌──────────────────────────────────────────────────┐
│  ←  AI Assistant          [Chat]  [Models]       │
├──────────────────────────────────────────────────┤
│                                                  │
│                   🧠 Gemma 4 E2B Q4              │
│                                                  │
│  ┌──────────────────────────────────────────┐    │
│  │  What are the prices on this page?      │    │ ← user (right)
│  └──────────────────────────────────────────┘    │
│                                                  │
│  ┌──────────────────────────────────────────┐    │
│  │  The page shows three pricing tiers:    │    │ ← assistant (left)
│  │  • Basic: $9/mo                         │    │
│  │  • Pro: $29/mo                          │    │
│  │  • Enterprise: $99/mo                   │    │
│  └──────────────────────────────────────────┘    │
│                                                  │
│                                                  │
├──────────────────────────────────────────────────┤
│  [Type a question...                       ] 🎤  │
└──────────────────────────────────────────────────┘
```

### Models tab (mobile)

Full-width model card list. Download, load, unload. Ollama endpoint config accessible from here too.

### Brain pill (iOS/Android)

34x34 tappable circle to the right of the URL field.

```
No model:
┌──────────────────────────────────────────────────┐
│  <  >  [  https://example.com            ]  (🧠) │
└──────────────────────────────────────────────────┘

Model loaded:
┌──────────────────────────────────────────────────┐
│  <  >  [  https://example.com          ]  (🧠👁) │
└──────────────────────────────────────────────────┘
```

**Tap** → navigates to the AI chat screen. No model loaded → Models tab. Model loaded → Chat tab. Ghost pill on first launch (stored in UserDefaults) to make AI discoverable.

---

## Floating Menu Integration

On all platforms (except Linux), the floating action menu gets a brain button:

```
iOS/Android floating menu:
┌───┐
│ ↻ │  Reload
│ 🔒│  Safari Auth
│ 🧠│  ← AI brain button
│ 🔖│  Bookmarks
│ 📜│  History
│ 📡│  Network
│ ⚙ │  Settings
└───┘

macOS floating menu:
Same — brain icon added to the menu items.
```

Tapping the brain in the floating menu:
- If no model loaded → opens panel/screen on Models tab
- If model loaded → opens panel/screen on Chat tab
- Same behavior as the URL bar brain pill

---

## Voice Input

**Not available on Linux.** Linux has no AI features.

**macOS requires Apple Silicon (M1+).** On Intel Macs, the entire AI feature is hidden — no brain pill, no panel, no AI section in settings. Check at startup with `ProcessInfo.processInfo.processorArchitecture` or `sysctl("hw.optional.arm64")`. If not Apple Silicon, `AIState.isAvailable` is `false` and all AI UI is suppressed.

### Voice routing

The 🎤 button in the chat input decides how to handle audio:

1. User taps 🎤 → browser records audio (max 30s, 16-bit PCM WAV, 16kHz mono)
2. Check loaded model's `audio` capability
3. **Model has `audio`** (e.g. Gemma 4 E2B): raw audio sent directly to model — single pass transcription + understanding (preferred, higher quality)
4. **Model lacks `audio`** (text-only): platform STT transcribes (SFSpeechRecognizer / SpeechRecognizer) → transcribed text sent as normal chat message (fallback)

### Recording UX

During recording:
- 🎤 button pulses red
- Countdown bar appears in the input area (starts full, decreases over 30 seconds)
- Tap 🎤 again to stop early
- Spinner while model processes, then response appears in chat

### Platform audio recording

| Platform | API | Notes |
|---|---|---|
| macOS | `AVAudioEngine` | Needs `NSMicrophoneUsageDescription` in Info.plist |
| iOS | `AVAudioEngine` | Same permission. Foreground only. |
| Android | `AudioRecord` | `RECORD_AUDIO` permission in manifest |
| Linux | N/A | No AI features |

Output format: 16-bit PCM WAV, 16kHz mono (~960KB for 30 seconds).

### MCP audio recording endpoint

#### `POST /v1/ai-record`

```json
// Start recording
{ "action": "start", "maxDuration": 30 }
→ { "success": true, "recording": true }

// Stop recording and return audio
{ "action": "stop" }
→ { "success": true, "audio": "<base64 WAV>", "durationMs": 4200 }

// Get recording status
{ "action": "status" }
→ { "success": true, "recording": true, "elapsedMs": 3100 }
```

---

## Download Progress — Implementation Notes

### Progress tracking

Downloads are managed by the CLI (macOS) or the app directly (mobile). Progress is reported as:

```json
{
  "modelId": "gemma-4-e2b-q4",
  "state": "downloading",
  "bytesDownloaded": 1258291200,
  "bytesTotal": 2500000000,
  "bytesPerSecond": 45000000,
  "etaSeconds": 28
}
```

### macOS: Shared model store — CLI and app

Both the CLI (`mollotov ai pull`) and the macOS app (Models tab download button) write to the same `~/.mollotov/models/` directory. Either can download, delete, or list models.

**App download:** User clicks Download in the panel's Models tab → `ModelDownloader` actor streams from HuggingFace via `URLSession` → progress bar on the card → writes to `~/.mollotov/models/<id>/model.gguf` → updates `registry.json`.

**CLI download:** User runs `mollotov ai pull gemma-4-e2b-q4` → CLI streams from HuggingFace → progress bar in terminal → writes to the same path → updates `registry.json`.

**Sync:** The macOS app watches `~/.mollotov/models/` via FSEvents (`DispatchSource.makeFileSystemObjectSource`). When the CLI downloads or deletes a model, the app's Models tab updates live — no restart needed. File-level locking (`flock`) on `registry.json` prevents corruption from concurrent writes.

### Mobile: App downloads directly

On iOS/Android, the app downloads models directly:
- iOS: `URLSession` background download task (survives app backgrounding)
- Android: `DownloadManager` system service (shows in notification bar)

Both write to the app's local model directory and update the local registry.

---

## Summary of New Files Needed

| Platform | File | Purpose |
|---|---|---|
| All | `FontAwesome6Free-Solid-900.otf` | Font file bundled in resources |
| macOS | `Mollotov/Views/AIChatPanel.swift` | 250px side panel with Chat + Models tabs, pin/unpin |
| macOS | `Mollotov/Views/AIChatView.swift` | Chat conversation view with input + mic button |
| macOS | `Mollotov/Views/AIModelListView.swift` | Model card list for panel's Models tab |
| macOS | `Mollotov/Views/AIStatusPill.swift` | Brain pill in URL bar — toggles side panel |
| macOS | `Mollotov/AI/ModelDownloader.swift` | HuggingFace download with progress |
| macOS | `Mollotov/AI/ModelRegistry.swift` | Approved models, fitness scoring, Ollama detection |
| macOS | `Mollotov/AI/AudioRecorder.swift` | AVAudioEngine 30s recorder, outputs PCM WAV |
| macOS | `Mollotov/AI/AIState.swift` | Published state: loaded model, capabilities, chat history |
| iOS | `Mollotov/Views/AIChatScreen.swift` | Full-screen chat with Chat + Models tabs |
| iOS | `Mollotov/Views/AIChatView.swift` | Chat conversation view |
| iOS | `Mollotov/Views/AIModelListView.swift` | Model card list |
| iOS | `Mollotov/Views/AIStatusPill.swift` | Brain pill + navigation trigger |
| iOS | `Mollotov/AI/ModelDownloader.swift` | Background download support |
| iOS | `Mollotov/AI/ModelRegistry.swift` | Curated model list + fitness |
| iOS | `Mollotov/AI/AudioRecorder.swift` | AVAudioEngine recorder |
| iOS | `Mollotov/AI/AIState.swift` | Published state |
| Android | `ui/AIChatScreen.kt` | Full-screen chat with tabs |
| Android | `ui/AIChatView.kt` | Chat conversation composable |
| Android | `ui/AIModelListView.kt` | Model card list composable |
| Android | `ui/AIStatusPill.kt` | Brain pill composable |
| Android | `ai/ModelDownloader.kt` | DownloadManager integration |
| Android | `ai/ModelRegistry.kt` | Curated model list + fitness |
| Android | `ai/AudioRecorder.kt` | AudioRecord recorder |
| Android | `ai/AIState.kt` | State holder |
| CLI | `src/ai/fitness.ts` | Hardware evaluation logic |
