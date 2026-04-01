# Mollotov Engine Monitoring Service

## Overview

The Engine Monitoring Service is a public-facing dashboard and API that tracks Gecko and Chromium upstream releases, monitors Mollotov's update pipeline, and provides compliance visibility to Apple App Review teams.

This service is the external proof of "active maintenance" required by Apple's Embedded Browser Engine Entitlement (see [browser-engines.md](browser-engines.md)).

---

## Architecture

### Components

1. **Monitoring API** — Internal service that polls upstream release feeds
2. **Dashboard Website** — Public-facing HTML/React dashboard
3. **GitHub Integration** — Automated PR creation and status tracking
4. **Status Page** — JSON API for App Review visibility
5. **Alerting** — Dead man's switch for failed automation

### Technology Stack

- **Dashboard:** Static site + API backend (Node.js + SQLite or PostgreSQL)
- **Release Monitoring:** Scheduled jobs (cron or Codex-driven)
- **GitHub Integration:** GitHub API + webhooks
- **Hosting:** Vercel, Netlify, or self-hosted (simple enough to run on a small VPS)

---

## Public Dashboard

### URL

```
https://monitor.mollotov.dev/
```

(or subdomain on main website)

### Display Sections

#### 1. Engine Status Overview

```
┌─────────────────────────────────────────────────────────┐
│                   ENGINE STATUS                         │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  Chromium (Blink)                                       │
│  ├─ Latest Upstream:   v125.0.6422.142 (released 2026-03-28) │
│  ├─ Current App:       v125.0.6422.138 (shipped)        │
│  ├─ Status:            ⏳ UPDATE IN PROGRESS             │
│  ├─ PR:                mollotov#1847 (Testing)          │
│  └─ Days to Deadline:  7 days remaining                 │
│                                                           │
│  Gecko (Firefox)                                        │
│  ├─ Latest Upstream:   v128.0 (released 2026-04-01)     │
│  ├─ Current App:       v128.0 (shipped)                 │
│  ├─ Status:            ✅ UP TO DATE                     │
│  ├─ PR:                mollotov#1845 (Merged)           │
│  └─ Days Since Update: 0 days                           │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

#### 2. Update Pipeline Status

```
┌─────────────────────────────────────────────────────────┐
│              CHROMIUM UPDATE PIPELINE (v125.0.6422.142)  │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  T+0 (2026-03-28)    Upstream release detected          │
│  T+4h (2026-03-28)   ✅ PR created by Claude            │
│  T+8h (2026-03-28)   ✅ Build succeeded (all tests OK) │
│  T+14h               ⏳ Manual review in progress       │
│  T+24h (deadline)    Planned submission to App Review  │
│                                                           │
│  PR #1847: [build] bump Chromium to v125.0.6422.142    │
│  └─ Created by: @codex-automation                       │
│  └─ Status: All checks passed, awaiting review          │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

#### 3. CVE Tracking

```
┌─────────────────────────────────────────────────────────┐
│                    SECURITY UPDATES                      │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  CHROMIUM v125.0.6422.142 addresses:                   │
│  ├─ CVE-2024-2996  (Critical) ✅ Shipped in Mollotov   │
│  ├─ CVE-2024-3156  (High)     ✅ Shipped in Mollotov   │
│  └─ CVE-2024-3249  (Medium)   ✅ Shipped in Mollotov   │
│                                                           │
│  GECKO v128.0 addresses:                                │
│  └─ [No new CVEs since v127.0]                          │
│                                                           │
│  Last security bulletin: Mozilla Advisory (2026-04-01)  │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

#### 4. Automation Health

```
┌─────────────────────────────────────────────────────────┐
│              AUTOMATION HEALTH                           │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  Last scan: 2026-04-01 10:43 UTC (20 minutes ago) ✅   │
│  Upstream feed status:                                  │
│  ├─ Chromium Dash: ✅ Reachable                        │
│  ├─ Chrome Releases Blog: ✅ Reachable                 │
│  ├─ Mozilla Release Calendar: ✅ Reachable             │
│  └─ Mozilla Security Advisories: ✅ Reachable          │
│                                                           │
│  Next scan: 2026-04-01 12:00 UTC (1 hour 20 min)       │
│  Dead man's switch: If no scan in 48 hours → ALERT     │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

### Interactive Features

- **Filter by Engine:** Show only Chromium updates, only Gecko, or both
- **Timeline View:** Historical record of all updates, PRs, and app releases
- **Notifications:** Optional email alerts when a deadline is approaching (day 10 of 15)
- **GitHub Links:** Direct links to PRs and issues
- **Download Logs:** Export full audit log for App Review submission

---

## Monitoring API

### Endpoints (Internal Use)

#### GET `/api/v1/engines/status`

Returns current status of all monitored engines.

```json
{
  "chromium": {
    "upstreamVersion": "125.0.6422.142",
    "upstreamReleaseDate": "2026-03-28T00:00:00Z",
    "appVersion": "125.0.6422.138",
    "appReleaseDate": "2026-03-25T08:30:00Z",
    "status": "update_in_progress",
    "prNumber": 1847,
    "prStatus": "testing",
    "cvesAddressed": [
      "CVE-2024-2996",
      "CVE-2024-3156",
      "CVE-2024-3249"
    ],
    "daysToDeadline": 7,
    "lastScanTime": "2026-04-01T10:43:00Z"
  },
  "gecko": {
    "upstreamVersion": "128.0",
    "upstreamReleaseDate": "2026-04-01T00:00:00Z",
    "appVersion": "128.0",
    "appReleaseDate": "2026-04-01T14:22:00Z",
    "status": "current",
    "prNumber": 1845,
    "prStatus": "merged",
    "cvesAddressed": [],
    "daysToDeadline": null,
    "lastScanTime": "2026-04-01T10:43:00Z"
  }
}
```

#### POST `/api/v1/engines/check`

Manually trigger a scan for new releases (idempotent).

```json
{
  "engines": ["chromium", "gecko"]
}
```

Response:

```json
{
  "scanStartedAt": "2026-04-01T10:44:00Z",
  "updatesFound": [
    {
      "engine": "chromium",
      "newVersion": "125.0.6422.142",
      "action": "pr_created",
      "prNumber": 1847,
      "timestamp": "2026-04-01T10:44:15Z"
    }
  ]
}
```

#### GET `/api/v1/health`

Simple liveness check (used by dead man's switch).

```json
{
  "status": "ok",
  "lastScanTime": "2026-04-01T10:43:00Z",
  "uptime": "720 hours",
  "scanFrequency": "2 hours"
}
```

---

## GitHub Integration

### Automated PR Creation

When a new upstream release is detected:

1. **Claude/Codex generates PR:**
   - Updates engine version in build files
   - Updates CHANGELOG with CVE list
   - Runs automated tests
   - Commits with message: `[build] bump {engine} to {version}`

2. **PR template includes:**
   - Upstream release notes link
   - CVE tracking table
   - Test results
   - Link to monitoring dashboard
   - "For App Review visibility" note

### Webhook Monitoring

Mollotov's CI/CD listens for GitHub webhook events:

- **PR created:** Auto-starts build
- **PR merged:** Triggers app release workflow
- **Deployment:** Dashboard updates with release date

### Example PR Template

```markdown
## Upstream Release

**Engine:** Chromium
**Version:** v125.0.6422.142
**Release Date:** 2026-03-28
**Release Notes:** https://chromereleases.googleblog.com/...

## Security Updates

| CVE | Severity | Fixed |
|-----|----------|-------|
| CVE-2024-2996 | Critical | ✅ |
| CVE-2024-3156 | High | ✅ |

## Verification

- [x] Automated tests passed
- [x] Manual spot-check completed
- [x] WPT score verified (95%+)
- [x] Test262 score verified (90%+)

## App Review Notes

This PR is part of Mollotov's automated engine maintenance pipeline.
Dashboard: https://monitor.mollotov.dev/
Policy: https://mollotov.dev/security/vulnerability-disclosure

**Deadline:** 2026-04-07 (15 days from upstream release)
```

---

## Compliance Checklist for App Review

Before submitting each app update to Apple, verify:

- [ ] Dashboard shows current status (upstream version, app version, deadline)
- [ ] PR links are visible and accessible
- [ ] All CVEs from the upstream release are listed
- [ ] Build test results are shown
- [ ] No CVEs in the upstream release are unaddressed
- [ ] Submission date is before the 15-day deadline
- [ ] CVE-2024-* entries link to official advisories

---

## Maintenance & Alerts

### Dead Man's Switch

If no scan occurs in 48 hours:

1. Dashboard shows **⚠️ AUTOMATION FAILURE** in red
2. Email alert sent to devops team
3. GitHub issue auto-created: "Monitoring service missed scan"
4. App Review metadata marks service as "unhealthy"

### Manual Overrides

Dashboard provides admin panel to:

- Mark an update as "manually reviewed and safe" (bypasses failed tests)
- Adjust deadlines (if production incident delays submission)
- Log manual CVE tracking (if automation missed one)

### Audit Trail

Every action is logged:

- Who triggered the scan (automation, manual, webhook)
- When PR was created and by what system
- When PR was tested and results
- When PR was merged
- When release was submitted to App Review
- When release was approved/rejected

---

## Example Workflow (Happy Path)

```
2026-03-28 00:00 — Chromium v125.0.6422.142 released
2026-03-28 02:15 — Mollotov monitoring detects release
2026-03-28 02:30 — Claude/Codex PR #1847 created automatically
2026-03-28 04:00 — GitHub workflow runs tests; all pass
2026-03-28 08:30 — Human reviewer approves PR
2026-03-28 09:00 — PR merged; release build triggered
2026-03-28 10:00 — App uploaded to Apple TestFlight
2026-03-28 14:00 — App approved by Apple
2026-03-29 00:00 — App released to public
2026-04-01 10:43 — Dashboard shows v125 as current; Chromium section says "✅ UP TO DATE"
```

---

## What This Proves to Apple

1. **Commitment to Security:** Real-time monitoring of upstream CVEs
2. **Automated Response:** PRs created within hours of release
3. **Compliance Tracking:** 15-day deadline is tracked and visible
4. **Transparency:** Public dashboard shows Apple reviewers the status anytime
5. **Reliability:** Health monitoring catches failures immediately

---

## Future Enhancements

- **Integration with GitHub Actions:** Native workflow file for scanning and PR creation
- **Slack Integration:** Notifications to devops on update detection and failures
- **Comparison Matrix:** Show which features are supported in each engine version
- **Performance Metrics:** Track WPT/Test262 scores over time
- **Region-Specific Releases:** Track which app versions are available in which regions

---

## Deployment

### Initial Setup

```bash
# 1. Create monitoring service repo/folder
# 2. Set up Node.js + SQLite backend
# 3. Configure cron job for 2-hour scan interval
# 4. Create GitHub PAT for PR creation
# 5. Deploy dashboard to Vercel/Netlify
# 6. Configure GitHub webhook for PR status updates
# 7. Set up email alerts for failures
```

### Minimal Requirements

- **Uptime:** 99.5% (can tolerate brief outages; manual scans can retry)
- **Latency:** Scan must complete in < 30 minutes (upstream feeds are fast)
- **Data Retention:** Keep 1 year of history (for App Review audits)
- **Scalability:** Single instance is sufficient; < 1000 API calls/day

---

## Security Considerations

- **No Private Keys in Dashboard:** Only show public metadata
- **No Credentials in Logs:** GitHub PAT must be masked
- **HTTPS Only:** All endpoints require HTTPS
- **Rate Limiting:** GitHub API requests must respect rate limits (60 req/min)
- **DDoS Protection:** Cloudflare or similar for public dashboard
