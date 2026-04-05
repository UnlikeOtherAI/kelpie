# Kelpie — Browser Engines & Platform Availability

## Overview

Kelpie is an LLM-controlled testing browser that needs to support multiple rendering engines across iOS, Android, macOS, and future desktop platforms. This document outlines which engines are available on each platform, the legal/regulatory constraints (especially Apple's 2026 regional restrictions), and the technical compliance requirements.

---

## Engine Availability by Platform

### iOS

| Engine | Status | Notes |
|---|---|---|
| **WebKit** (WKWebView) | Always available | Only engine legally available in US, Canada, Australia, and non-EU regions |
| **Gecko** (Firefox) | EU/Japan/UK only | Via Embedded Browser Engine Entitlement; region-gated by Apple |
| **Chromium/Blink** (Chrome) | EU/Japan/UK only | Via Embedded Browser Engine Entitlement; region-gated by Apple |

**Current Implementation:** iOS apps use `WKWebView` exclusively. Future versions targeting EU/Japan/UK can conditionally request and use Gecko or Chromium after obtaining Apple's Embedded Browser Engine Entitlement.

### Android

| Engine | Status | Notes |
|---|---|---|
| **Chromium/Blink** (WebView) | Always available | Android WebView is Chromium-based; supports Chrome DevTools Protocol (CDP) |
| **Gecko** (Firefox) | Not embedded | Available as standalone app but not as embeddable engine on Android |

**Current Implementation:** Android apps use the system Android WebView (Chromium-based). Alternative engines are not currently embedded.

### macOS

| Engine | Status | Notes |
|---|---|---|
| **WebKit** (WKWebView) | Always available | Safari-compatible rendering |
| **Chromium/Blink** (CEF) | Always available | Chromium Embedded Framework; no entitlement required on macOS |
| **Gecko** (Firefox Remote Protocol) | Available — CDP subprocess | Spawns Firefox.app with `--remote-debugging-port`; driven via Firefox Remote Protocol (CDP-compatible WebSocket) |

**Current Implementation:** macOS apps support WebKit, CEF (Chromium), and Gecko (Firefox) with runtime switching via the renderer abstraction layer. Gecko spawns Firefox.app as a headless subprocess and drives it via the CDP-compatible Firefox Remote Protocol.

### Windows

| Engine | Status | Notes |
|---|---|---|
| **Chromium/Blink** (WebView2) | Always available | Windows WebView2; requires Windows 10+; CDP support via `webdriver` protocol |
| **Gecko** | Open source, embeddable | Mozilla's GeckoView; build from source or use pre-compiled binaries |
| **Ladybird** | Early stage | New independent engine; not production-ready as of 2026 |

**Future Implementation:** Desktop platforms will prioritize WebView2 (Chromium) with optional Gecko support.

### Linux

| Engine | Status | Notes |
|---|---|---|
| **Chromium/Blink** | Always available | GTK/Qt bindings available; supports CDP |
| **Gecko** | Embeddable | GeckoView available; full control over engine version |
| **WebKit2GTK** | Always available | GTK native; WebKit engine |

**Future Implementation:** Linux desktop will use one of these as the base, with preference for Chromium or Gecko for consistency with other platforms.

---

## Apple's Regulatory Framework (2026)

### Regional Access Control

As of April 1, 2026, Apple legally requires allowing alternative browser engines (Gecko, Chromium/Blink) in **specific regions only**. Kelpie must respect these boundaries.

#### Eligible Regions for Alternative Engines

**European Union** (27 member states + overseas territories):
- Austria, Belgium, Bulgaria, Croatia, Cyprus, Czech Republic, Denmark, Estonia, Finland, France, Germany, Greece, Hungary, Ireland, Italy, Latvia, Lithuania, Luxembourg, Malta, Netherlands, Poland, Portugal, Romania, Slovakia, Slovenia, Spain, Sweden
- Also: French Guiana, Guadeloupe, Martinique, Mayotte, Réunion, Saint Martin, Azores, Madeira, Canary Islands

**Japan**
- Full alternative engine support under the Mobile Software Competition Act (effective December 2025)

**United Kingdom** (pending finalization)
- CMA has mandated implementation; expected enforcement 2026

**Everywhere Else** (US, Canada, Australia, etc.)
- WebKit only; alternative engines are prohibited by Apple at the OS level

### Apple's Entitlements (Required for EU/Japan/UK)

To use Gecko or Chromium on iOS in eligible regions, you must obtain one of these entitlements from Apple:

1. **Web Browser Engine Entitlement** — For dedicated browser apps (full-featured web browsers)
2. **Embedded Browser Engine Entitlement** — For apps that embed a browser (like Kelpie, a testing tool)

Both entitlements require:

- **Primary Purpose Declaration:** The app's primary purpose must be web browsing or testing web content
- **Vulnerability Policy:** Public, published policy for reporting security flaws (URL required)
- **30-Day Patch Commitment:** Legally binding commitment to patch exploited vulnerabilities within 30 days
- **15-Day Update Rule:** Must submit app update to Apple within 15 calendar days of the embedded engine releasing a new version
- **Web Platform Tests (WPT):** Engine must pass 90%+ of standard WPT suite on iOS
- **Test262:** Engine must pass 80%+ of Test262 (JavaScript conformance) on iOS
- **Regional Gating:** App binary must programmatically verify device region and disable alternative engines outside eligible zones

### Apple's Rejection Criteria (Even with Entitlement)

Apple can still reject your app if:

1. **Incomplete Functionality (Guideline 2.1):** If the reviewer is in the US and the alternative engine is disabled, Apple may reject for being an "incomplete" app
   - *Mitigation:* Clearly document in App Review Notes that the app is region-aware and fully functional with WebKit
2. **Security Failures:** Missing or outdated vulnerability disclosure policy, unpatched known exploits
3. **Performance Degradation:** Engine fails WPT or Test262, or causes battery drain / stability issues on Apple Silicon
4. **Malicious Compliance:** Apple may delay entitlement approval or nitpick UI/UX details ("mimics system elements too closely")
5. **Regional Violations:** App activates alternative engine for US users; Apple will flag and reject

---

## Kelpie's Compliance Strategy

### Entitlement Application

For Kelpie to use Gecko or Chromium on iOS in EU/Japan/UK regions:

1. **Request the Embedded Browser Engine Entitlement** via Apple Developer Portal
2. **Publish a Security/Vulnerability Policy** on Kelpie's website; include:
   - How security flaws are reported (email, HackerOne, etc.)
   - Expected response timeline (e.g., "Critical: 5 days, High: 15 days")
   - Confirmation that patches will be submitted to App Review within 15 days of upstream release
3. **Demonstrate Compliance in App Review Notes:**
   - Explain that Kelpie is an LLM-controlled testing tool for developers
   - State that the app is region-gated: alternative engines only activate in EU/Japan/UK
   - Show video evidence of the app working with both WebKit (US mode) and Gecko/Chromium (EU mode)
   - Reference the public monitoring dashboard (see below) proving active engine maintenance

### Region-Gating Implementation

Kelpie must programmatically check device region and conditionally enable alternative engines:

```swift
// Pseudocode for iOS
enum AvailableEngines {
    case webkitOnly
    case webkitAndAlternative(gecko: Bool, chromium: Bool)
}

func detectAvailableEngines() -> AvailableEngines {
    let locale = Locale.current
    let countryCode = locale.region?.identifier ?? ""

    let euCountries = ["AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE"]
    let jpCode = "JP"
    let ukCode = "GB"

    if euCountries.contains(countryCode) || countryCode == jpCode || countryCode == ukCode {
        return .webkitAndAlternative(gecko: true, chromium: true)
    } else {
        return .webkitOnly
    }
}
```

**Important:** The app **must check region at runtime** for every session. Apple may test with devices in different regions to verify region-gating works correctly.

### Automated Maintenance (15-Day Update Rule)

Since Kelpie uses Claude + Codex to automate browser engine updates, the compliance pipeline must:

1. **Monitor Official Release Channels:**
   - Chromium: [Chromium Dash](https://chromiumdash.appspot.com/) + [Chrome Releases Blog](https://chromereleases.googleblog.com/)
   - Gecko: [Mozilla Release Calendar](https://wiki.mozilla.org/Release_Calendar) + [Security Advisories](https://www.mozilla.org/security/known-issues/)

2. **Trigger PR Generation Automatically:**
   - T+0: Upstream stable release detected
   - T+4h: Claude/Codex generates PR with bumped engine version
   - T+24h: Automated build and test; if failures, alert human reviewer
   - T+10 days: If not yet submitted to App Review, trigger "Critical Failure" alert

3. **Track Compliance Publicly:**
   - Dashboard shows current upstream version
   - Dashboard shows current App Store version
   - Dashboard shows PR/submission status ("Scanning," "PR Created," "Testing," "In Review," "Approved")
   - Dashboard tracks CVEs addressed in each build

### Security & Patching

**30-Day "Active Exploit" Rule:** If a critical vulnerability is being actively exploited:
- Claude/Codex should prioritize this PR as "CRITICAL"
- Track CVE-ID and exploit status
- Ensure submission to App Review happens within 30 days, not 15

**Multiprocess Architecture:** Both Gecko and Chromium must run in separate processes from the main app UI:
- Prevents render crashes from killing the app
- Allows OS to apply JIT memory restrictions
- Improves stability and security

---

## Technical Requirements

### Web Platform Tests (WPT)

Both Gecko and Chromium already pass 90%+ of WPT by default. However, verify on iOS device:

```bash
# After building, run on iOS simulator/device:
# This is Apple's test suite; confirm no regressions from your wrapper
```

Kelpie's "wrapper" (MCP control layer, LLM orchestration) must not degrade WPT scores. If it does, Apple will reject the app.

### Test262 (JavaScript Conformance)

Gecko and Chromium both pass 80%+ of Test262. Again, verify no regressions from the Kelpie layer.

### Info.plist Entries (iOS)

```xml
<!-- Required for Embedded Browser Engine Entitlement -->
<key>NSLocalNetworkUsageDescription</key>
<string>Kelpie connects to your development machine over the local network to receive automated testing and MCP commands.</string>

<!-- For alternative engine support -->
<key>NSBonjourServices</key>
<array>
  <string>_kelpie._tcp</string>
</array>

<!-- If using Chromium/Gecko -->
<key>EmbeddedBrowserEngineEntitlement</key>
<true/>
```

### JIT Memory and Compilation

Apple provides special APIs for high-performance JIT:
- iOS: Use `MAP_JIT` memory regions via `NSRegularExpression` or direct `mmap` calls
- Gecko and Chromium already use these on iOS; ensure your build flags don't disable them

---

## Kelpie's Monitoring & Compliance Dashboard

To satisfy Apple's requirement for "active maintenance," Kelpie will have a public dashboard. For the full service architecture and API specification, see [engine-monitoring.md](engine-monitoring.md).

The dashboard will show:

1. **Current Engine Status**
   - Upstream Gecko latest version
   - Upstream Chromium latest version
   - Kelpie's currently shipped version

2. **Update Pipeline Status**
   - "Scanning for updates..." (automated)
   - "PR created" with link
   - "Build testing..." with test results
   - "Submitted to App Review" with submission date
   - "Approved and shipped"

3. **CVE Tracking**
   - List of CVEs addressed in current build
   - Security bulletin links to upstream advisories

4. **Automation Health**
   - Last successful scan timestamp
   - Any failures in Claude/Codex automation (with alert)
   - Dead man's switch: if no scan happens in 48 hours, alert

This dashboard is **public-facing** (for App Review transparency) and **not behind authentication** (so Apple reviewers can verify compliance without special access).

---

## Implementation Checklist

### Before App Submission (EU/Japan/UK)

- [ ] Create public vulnerability disclosure policy page on website
- [ ] Submit Embedded Browser Engine Entitlement request to Apple Developer Portal
- [ ] Verify region-gating logic in code (check `Locale.region`)
- [ ] Build and test on iOS device in EU/US (verify engine switch behavior)
- [ ] Run WPT and Test262 on device; confirm no regressions
- [ ] Set up automated Chromium/Gecko monitoring (mDNS, release feeds)
- [ ] Implement Claude/Codex PR generation pipeline (test with a mock release)
- [ ] Create compliance monitoring dashboard (even if empty initially)
- [ ] Prepare video demo showing LLM controlling browser with Gecko/Chromium in EU mode
- [ ] Write App Review Notes explaining region-gating and automated maintenance

### Ongoing (After Approval)

- [ ] Monitor upstream releases daily (automated)
- [ ] Generate and review PR within 48 hours of upstream release
- [ ] Test on actual device (iOS simulator may not catch all issues)
- [ ] Submit to App Review by day 10 (buffer for delays)
- [ ] Track CVE advisories; expedite "active exploit" patches
- [ ] Maintain public dashboard (update on every submission)
- [ ] Publish monthly or quarterly transparency report (optional but recommended)

---

## Restrictions & Edge Cases

### Users Traveling Outside Eligible Regions

If a user travels outside EU/Japan/UK for more than 30 days:
- Apple may revert their device to WebKit-only mode
- Kelpie will fall back to WKWebView automatically
- No data loss, but MCP automation may degrade slightly (some features may be WKWebView-only)

### TestFlight Testing

For early testing with developers outside eligible regions:
- Standard TestFlight (90-day builds) does not support alternative engines outside EU/Japan/UK
- Exception: Apple may grant "browser vendor" status for global TestFlight testing if you can prove you're an established browser project
- Kelpie likely doesn't qualify; recommend testing with TestFlight only in EU region

### App Store Review Edge Cases

Apple may reject if:
- The app's "core functionality" (e.g., web testing) is unusable without the alternative engine (Kelpie works fine with WebKit, so this is not a risk)
- The app attempts to download and run engines outside the Apple-approved distribution channel (always use the Embedded entitlement, never try to sideload engines)
- The app fails to gate engines by region (most common reason for rejection)

---

## Future Platforms: Windows, Linux

For desktop platforms, entitlements are not required. Both Gecko and Chromium can be embedded freely:

- **Windows:** WebView2 (Chromium) is recommended for simplicity; Gecko also available
- **Linux:** Chromium (GTK/Qt bindings) or Gecko (GeckoView) are both fine; no licensing concerns

These platforms do not require Apple's approval and can be updated independently.

---

## References

- [Apple Developer: Using alternative browser engines in the EU](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_developer_web-browser-engine)
- [Apple Developer: Embedded Browser Engine Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_developer_embedded-browser-engine)
- [Chrome Releases Blog](https://chromereleases.googleblog.com/)
- [Chromium Dash](https://chromiumdash.appspot.com/)
- [Mozilla Release Calendar](https://wiki.mozilla.org/Release_Calendar)
- [Web Platform Tests (WPT)](https://wpt.fyi/)
- [Test262 (JavaScript Standard Test Suite)](https://github.com/tc39/test262)
