# Monitoring Service Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an LLM-agent-driven service that monitors Chromium and Gecko upstream releases plus CVEs, tracks update progress using GitHub Issues as the sole datastore, and serves a public dashboard for Apple App Review compliance visibility.

**Architecture:** A Node.js/TypeScript API in `monitoring/api/` runs a tool-calling LLM agent (Minimax 2.7 via OpenAI-compatible API) on a 2-hour cron schedule. The agent fetches upstream release JSON, uses Firecrawl to scrape pages that have no JSON feed (Chrome release notes, Mozilla advisories), looks up CVE details from the NVD API, then reads/writes GitHub Issues with structured metadata embedded in the body. A Vite+React frontend in `monitoring/frontend/` reads the monitoring API and renders a real-time compliance dashboard. No database — GitHub Issues are the datastore.

**Tech Stack:** Node.js 20+, TypeScript, Hono (API server), OpenAI SDK (Minimax 2.7 via baseURL override), `@octokit/rest`, `@mendable/firecrawl-js`, `node-cron`, React 19, Vite 6, pnpm workspaces

---

## Data Sources

| Source | URL | Format |
|---|---|---|
| Chromium stable releases | `https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Linux&num=5&offset=0` | JSON |
| Firefox versions | `https://product-details.mozilla.org/1.0/firefox_versions.json` | JSON |
| Chrome release notes | `https://chromereleases.googleblog.com/` | HTML → Firecrawl |
| Mozilla security advisories | `https://www.mozilla.org/security/advisories/` | HTML → Firecrawl |
| NVD CVE lookup | `https://services.nvd.nist.gov/rest/json/cves/2.0?cveId={id}` | JSON |
| NVD CVE search | `https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch={engine}&resultsPerPage=20` | JSON |

## GitHub Issues Schema

### Labels

```
engine:chromium     #d93f0b   Chromium/Blink engine
engine:gecko        #e4e669   Gecko/Firefox engine
type:release        #0075ca   Upstream release update
type:cve            #e11d48   Security vulnerability
priority:critical   #b60205   Actively exploited / CVSS 9+
priority:high       #d93f0b   CVSS 7-8.9
priority:medium     #e4e669   CVSS 4-6.9
priority:low        #c2e0c6   CVSS < 4
status:pending      #cccccc   Detected, not started
status:pr-open      #0075ca   PR in progress
status:pr-merged    #6f42c1   PR merged, pending App Review
status:shipped      #28a745   Shipped in App Store
status:dismissed    #dddddd   Not applicable / skipped
```

### Issue Title Format

- Release: `[chromium] Release v125.0.6422.142`
- CVE: `[chromium] CVE-2024-2996 — Critical: Use after free in WebAudio`

### Issue Body Format

Each issue body ends with a machine-readable metadata block (HTML comment, invisible in rendered view):

```markdown
## Engine Update: Chromium v125.0.6422.142

**Release Date:** 2026-03-28
**Deadline:** 2026-04-12 (15 days from upstream release)
**Status:** In Progress

### Security Fixes

- CVE-2024-2996 (Critical) — Use after free in WebAudio
- CVE-2024-3156 (High) — Type confusion in V8

### Links

- [Upstream release notes](https://chromereleases.googleblog.com/...)
- [PR #1847](https://github.com/UnlikeOtherAI/kelpie/pull/1847)

---

<!-- MONITORING_METADATA
{
  "engine": "chromium",
  "type": "release",
  "version": "125.0.6422.142",
  "milestone": 125,
  "releaseDate": "2026-03-28",
  "deadline": "2026-04-12",
  "cves": [
    { "id": "CVE-2024-2996", "severity": "Critical", "description": "Use after free in WebAudio" }
  ],
  "upstreamUrl": "https://chromereleases.googleblog.com/...",
  "branchName": "engine-update/chromium-125.0.6422.142",
  "prNumber": null,
  "status": "pending"
}
-->
```

## Branch Naming Convention

```
engine-update/{engine}-{version}     # Release update PR
security/{engine}-{cve-id}           # CVE-specific hotfix PR
```

Examples:
- `engine-update/chromium-125.0.6422.142`
- `engine-update/gecko-128.0`
- `security/chromium-CVE-2024-2996`
- `security/gecko-CVE-2024-3001`

The agent matches open PRs using:
```typescript
const BRANCH_PATTERNS = {
  release: /^engine-update\/(chromium|gecko)-[\d.]+$/,
  cve:     /^security\/(chromium|gecko)-CVE-\d{4}-\d+$/,
}
```

---

## Task 1: Scaffold the monorepo packages

**Files:**
- Create: `monitoring/api/package.json`
- Create: `monitoring/api/tsconfig.json`
- Create: `monitoring/api/src/index.ts`
- Create: `monitoring/frontend/package.json`
- Create: `monitoring/frontend/tsconfig.json`
- Create: `monitoring/frontend/index.html`
- Create: `monitoring/frontend/vite.config.ts`
- Create: `monitoring/frontend/src/main.tsx`
- Create: `monitoring/.env.example`

**Step 1: Create the API package**

`monitoring/api/package.json`:
```json
{
  "name": "@kelpie/monitoring-api",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "main": "dist/index.js",
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsc",
    "test": "node --experimental-vm-modules node_modules/.bin/jest",
    "lint": "tsc --noEmit"
  },
  "dependencies": {
    "@mendable/firecrawl-js": "^1.0.0",
    "@octokit/rest": "^21.0.0",
    "hono": "^4.0.0",
    "@hono/node-server": "^1.0.0",
    "node-cron": "^3.0.0",
    "openai": "^4.0.0",
    "zod": "^3.0.0"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "@types/node-cron": "^3.0.0",
    "jest": "^29.0.0",
    "ts-jest": "^29.0.0",
    "tsx": "^4.0.0",
    "typescript": "^5.0.0"
  }
}
```

`monitoring/api/tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
```

`monitoring/api/src/index.ts`:
```typescript
// Entry point — wired up in Task 9
export {};
```

**Step 2: Create the frontend package**

`monitoring/frontend/package.json`:
```json
{
  "name": "@kelpie/monitoring-frontend",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  },
  "devDependencies": {
    "@types/react": "^19.0.0",
    "@types/react-dom": "^19.0.0",
    "@vitejs/plugin-react": "^4.0.0",
    "typescript": "^5.0.0",
    "vite": "^6.0.0"
  }
}
```

`monitoring/frontend/vite.config.ts`:
```typescript
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': 'http://localhost:3001',
    },
  },
})
```

**Step 3: Create `.env.example`**

`monitoring/.env.example`:
```
# GitHub
GITHUB_TOKEN=ghp_...
GITHUB_OWNER=UnlikeOtherAI
GITHUB_REPO=kelpie

# Minimax 2.7 (OpenAI-compatible)
MINIMAX_API_KEY=...
MINIMAX_BASE_URL=https://api.minimax.chat/v1
MINIMAX_MODEL=minimax-text-01

# Alternatively, use Claude Haiku
# ANTHROPIC_API_KEY=...
# LLM_PROVIDER=anthropic

# Firecrawl
FIRECRAWL_API_KEY=fc-...

# NVD (optional — anonymous gets rate-limited)
NVD_API_KEY=...

# Monitoring
PORT=3001
SCAN_CRON=0 */2 * * *
```

**Step 4: Install dependencies in both packages**

```bash
cd monitoring/api && pnpm install
cd ../frontend && pnpm install
```

**Step 5: Commit**

```bash
git add monitoring/
git commit -m "chore: scaffold monitoring service packages"
```

---

## Task 2: GitHub label seeding

**Files:**
- Create: `monitoring/api/src/github/labels.ts`
- Create: `monitoring/api/src/github/labels.test.ts`

**Step 1: Write the failing test**

`monitoring/api/src/github/labels.test.ts`:
```typescript
import { buildLabelRequests, LABELS } from './labels.js'

describe('buildLabelRequests', () => {
  it('returns one request per label', () => {
    const requests = buildLabelRequests()
    expect(requests).toHaveLength(LABELS.length)
  })

  it('each request has name, color, and description', () => {
    const requests = buildLabelRequests()
    for (const r of requests) {
      expect(r.name).toBeTruthy()
      expect(r.color).toMatch(/^[0-9a-f]{6}$/)
      expect(r.description).toBeTruthy()
    }
  })

  it('colors do not have leading hash', () => {
    const requests = buildLabelRequests()
    for (const r of requests) {
      expect(r.color).not.toContain('#')
    }
  })
})
```

Run: `pnpm test -- labels`
Expected: FAIL with "Cannot find module './labels.js'"

**Step 2: Implement label definitions**

`monitoring/api/src/github/labels.ts`:
```typescript
export interface LabelDef {
  name: string
  color: string   // 6-char hex without #
  description: string
}

export const LABELS: LabelDef[] = [
  // Engine
  { name: 'engine:chromium', color: 'd93f0b', description: 'Chromium/Blink engine' },
  { name: 'engine:gecko',    color: 'e4e669', description: 'Gecko/Firefox engine' },

  // Type
  { name: 'type:release', color: '0075ca', description: 'Upstream release update' },
  { name: 'type:cve',     color: 'e11d48', description: 'Security vulnerability' },

  // Priority
  { name: 'priority:critical', color: 'b60205', description: 'Actively exploited / CVSS 9+' },
  { name: 'priority:high',     color: 'd93f0b', description: 'CVSS 7-8.9' },
  { name: 'priority:medium',   color: 'e4e669', description: 'CVSS 4-6.9' },
  { name: 'priority:low',      color: 'c2e0c6', description: 'CVSS below 4' },

  // Status
  { name: 'status:pending',    color: 'cccccc', description: 'Detected, not started' },
  { name: 'status:pr-open',    color: '0075ca', description: 'PR in progress' },
  { name: 'status:pr-merged',  color: '6f42c1', description: 'PR merged, pending App Review' },
  { name: 'status:shipped',    color: '28a745', description: 'Shipped in App Store' },
  { name: 'status:dismissed',  color: 'dddddd', description: 'Not applicable / skipped' },
]

export function buildLabelRequests() {
  return LABELS.map(({ name, color, description }) => ({ name, color, description }))
}
```

**Step 3: Run test**

```bash
pnpm test -- labels
```
Expected: PASS (3 tests)

**Step 4: Add the seed script**

`monitoring/api/src/github/labels.ts` — append:
```typescript
import { Octokit } from '@octokit/rest'

export async function seedLabels(octokit: Octokit, owner: string, repo: string) {
  const existing = await octokit.issues.listLabelsForRepo({ owner, repo, per_page: 100 })
  const existingNames = new Set(existing.data.map(l => l.name))

  for (const label of LABELS) {
    if (existingNames.has(label.name)) {
      await octokit.issues.updateLabel({ owner, repo, ...label })
    } else {
      await octokit.issues.createLabel({ owner, repo, ...label })
    }
  }
}
```

**Step 5: Commit**

```bash
git add monitoring/api/src/github/labels.ts monitoring/api/src/github/labels.test.ts
git commit -m "feat(monitoring): github label taxonomy + seed function"
```

---

## Task 3: Upstream release source fetchers

**Files:**
- Create: `monitoring/api/src/sources/chromium.ts`
- Create: `monitoring/api/src/sources/gecko.ts`
- Create: `monitoring/api/src/sources/chromium.test.ts`
- Create: `monitoring/api/src/sources/gecko.test.ts`

**Step 1: Write Chromium test**

`monitoring/api/src/sources/chromium.test.ts`:
```typescript
import { parseChromiumRelease } from './chromium.js'

describe('parseChromiumRelease', () => {
  const raw = [{
    version: '125.0.6422.142',
    milestone: 125,
    time: 1711584000000,
    channel: 'Stable',
    platform: 'Linux',
    previous_version: '125.0.6422.138',
    hashes: { chromium: 'abc123' },
    chromium_main_branch_position: 1234567,
  }]

  it('extracts version and milestone', () => {
    const release = parseChromiumRelease(raw)
    expect(release.version).toBe('125.0.6422.142')
    expect(release.milestone).toBe(125)
  })

  it('converts ms timestamp to ISO date string', () => {
    const release = parseChromiumRelease(raw)
    expect(release.releaseDate).toMatch(/^\d{4}-\d{2}-\d{2}$/)
  })

  it('computes 15-day deadline', () => {
    const release = parseChromiumRelease(raw)
    const deadline = new Date(release.deadline)
    const releaseDate = new Date(release.releaseDate)
    const diff = (deadline.getTime() - releaseDate.getTime()) / (1000 * 60 * 60 * 24)
    expect(diff).toBe(15)
  })
})
```

Run: `pnpm test -- chromium`
Expected: FAIL

**Step 2: Implement Chromium source**

`monitoring/api/src/sources/chromium.ts`:
```typescript
export interface ChromiumRelease {
  engine: 'chromium'
  version: string
  milestone: number
  releaseDate: string     // YYYY-MM-DD
  deadline: string        // YYYY-MM-DD (releaseDate + 15 days)
  previousVersion: string
  upstreamUrl: string
}

const CHROMIUM_API = 'https://chromiumdash.appspot.com/fetch_releases?channel=Stable&platform=Linux&num=3&offset=0'
const RELEASE_NOTES_BASE = 'https://chromereleases.googleblog.com/'
const DEADLINE_DAYS = 15

export function parseChromiumRelease(raw: any[]): ChromiumRelease {
  const r = raw[0]
  const releaseDate = new Date(r.time).toISOString().slice(0, 10)
  const deadline = new Date(r.time + DEADLINE_DAYS * 864e5).toISOString().slice(0, 10)

  return {
    engine: 'chromium',
    version: r.version,
    milestone: r.milestone,
    releaseDate,
    deadline,
    previousVersion: r.previous_version,
    upstreamUrl: RELEASE_NOTES_BASE,
  }
}

export async function fetchLatestChromiumRelease(): Promise<ChromiumRelease> {
  const res = await fetch(CHROMIUM_API)
  if (!res.ok) throw new Error(`Chromium Dash returned ${res.status}`)
  const data = await res.json()
  return parseChromiumRelease(data)
}
```

Run: `pnpm test -- chromium`
Expected: PASS

**Step 3: Write Gecko test**

`monitoring/api/src/sources/gecko.test.ts`:
```typescript
import { parseGeckoRelease } from './gecko.js'

describe('parseGeckoRelease', () => {
  const raw = {
    LATEST_FIREFOX_VERSION: '128.0',
    LAST_RELEASE_DATE: '2026-04-01',
    NEXT_RELEASE_DATE: '2026-05-13',
    FIREFOX_ESR: '115.13.0esr',
  }

  it('extracts the stable version', () => {
    const release = parseGeckoRelease(raw)
    expect(release.version).toBe('128.0')
  })

  it('uses LAST_RELEASE_DATE as the release date', () => {
    const release = parseGeckoRelease(raw)
    expect(release.releaseDate).toBe('2026-04-01')
  })

  it('computes 15-day deadline from releaseDate', () => {
    const release = parseGeckoRelease(raw)
    const deadline = new Date(release.deadline)
    const releaseDate = new Date(release.releaseDate)
    const diff = (deadline.getTime() - releaseDate.getTime()) / (1000 * 60 * 60 * 24)
    expect(diff).toBe(15)
  })
})
```

Run: `pnpm test -- gecko`
Expected: FAIL

**Step 4: Implement Gecko source**

`monitoring/api/src/sources/gecko.ts`:
```typescript
export interface GeckoRelease {
  engine: 'gecko'
  version: string
  releaseDate: string
  deadline: string
  nextReleaseDate: string
  esr: string
  upstreamUrl: string
}

const GECKO_API = 'https://product-details.mozilla.org/1.0/firefox_versions.json'
const ADVISORIES_URL = 'https://www.mozilla.org/security/advisories/'
const DEADLINE_DAYS = 15

export function parseGeckoRelease(raw: any): GeckoRelease {
  const releaseDate = raw.LAST_RELEASE_DATE
  const deadlineDate = new Date(new Date(releaseDate).getTime() + DEADLINE_DAYS * 864e5)
    .toISOString().slice(0, 10)

  return {
    engine: 'gecko',
    version: raw.LATEST_FIREFOX_VERSION,
    releaseDate,
    deadline: deadlineDate,
    nextReleaseDate: raw.NEXT_RELEASE_DATE,
    esr: raw.FIREFOX_ESR,
    upstreamUrl: ADVISORIES_URL,
  }
}

export async function fetchLatestGeckoRelease(): Promise<GeckoRelease> {
  const res = await fetch(GECKO_API)
  if (!res.ok) throw new Error(`Mozilla product-details returned ${res.status}`)
  const data = await res.json()
  return parseGeckoRelease(data)
}
```

Run: `pnpm test -- gecko`
Expected: PASS

**Step 5: Commit**

```bash
git add monitoring/api/src/sources/
git commit -m "feat(monitoring): Chromium and Gecko release source fetchers"
```

---

## Task 4: NVD CVE lookup

**Files:**
- Create: `monitoring/api/src/sources/cve.ts`
- Create: `monitoring/api/src/sources/cve.test.ts`

**Step 1: Write the test**

`monitoring/api/src/sources/cve.test.ts`:
```typescript
import { parseCveRecord } from './cve.js'

describe('parseCveRecord', () => {
  const rawVuln = {
    cve: {
      id: 'CVE-2024-2996',
      published: '2024-03-26T18:15:00.000',
      lastModified: '2024-03-28T12:00:00.000',
      descriptions: [
        { lang: 'en', value: 'Use after free in WebAudio in Google Chrome prior to 123.0.6312.86.' },
        { lang: 'es', value: 'Uso después de libre...' },
      ],
      metrics: {
        cvssMetricV31: [{
          cvssData: { baseScore: 9.8, baseSeverity: 'CRITICAL' },
          type: 'Primary',
        }],
      },
    },
  }

  it('extracts id and description', () => {
    const cve = parseCveRecord(rawVuln)
    expect(cve.id).toBe('CVE-2024-2996')
    expect(cve.description).toContain('WebAudio')
  })

  it('picks English description', () => {
    const cve = parseCveRecord(rawVuln)
    expect(cve.description).not.toContain('libre')
  })

  it('extracts CVSS severity', () => {
    const cve = parseCveRecord(rawVuln)
    expect(cve.severity).toBe('Critical')
    expect(cve.cvssScore).toBe(9.8)
  })
})
```

Run: `pnpm test -- cve`
Expected: FAIL

**Step 2: Implement CVE source**

`monitoring/api/src/sources/cve.ts`:
```typescript
export interface CveRecord {
  id: string
  description: string
  severity: 'Critical' | 'High' | 'Medium' | 'Low' | 'Unknown'
  cvssScore: number | null
  publishedDate: string
  url: string
}

const NVD_BASE = 'https://services.nvd.nist.gov/rest/json/cves/2.0'

function normalizeSeverity(s?: string): CveRecord['severity'] {
  switch (s?.toUpperCase()) {
    case 'CRITICAL': return 'Critical'
    case 'HIGH':     return 'High'
    case 'MEDIUM':   return 'Medium'
    case 'LOW':      return 'Low'
    default:         return 'Unknown'
  }
}

export function parseCveRecord(vuln: any): CveRecord {
  const cve = vuln.cve
  const desc = cve.descriptions.find((d: any) => d.lang === 'en')?.value ?? ''

  // Try CVSS v3.1 first, fall back to v3.0, then v2
  const metrics =
    cve.metrics?.cvssMetricV31?.[0] ??
    cve.metrics?.cvssMetricV30?.[0] ??
    cve.metrics?.cvssMetricV2?.[0] ?? null

  const score = metrics?.cvssData?.baseScore ?? null
  const severity = normalizeSeverity(
    metrics?.cvssData?.baseSeverity ?? metrics?.baseSeverity
  )

  return {
    id: cve.id,
    description: desc,
    severity,
    cvssScore: score,
    publishedDate: cve.published.slice(0, 10),
    url: `https://nvd.nist.gov/vuln/detail/${cve.id}`,
  }
}

export async function fetchCve(cveId: string, apiKey?: string): Promise<CveRecord> {
  const url = `${NVD_BASE}?cveId=${encodeURIComponent(cveId)}`
  const headers: Record<string, string> = {}
  if (apiKey) headers['apiKey'] = apiKey

  const res = await fetch(url, { headers })
  if (!res.ok) throw new Error(`NVD returned ${res.status} for ${cveId}`)

  const data = await res.json()
  if (!data.vulnerabilities?.length) throw new Error(`CVE ${cveId} not found in NVD`)

  return parseCveRecord(data.vulnerabilities[0])
}

export async function searchRecentCves(engine: 'chromium' | 'gecko', apiKey?: string): Promise<CveRecord[]> {
  const keyword = engine === 'chromium' ? 'Google Chrome' : 'Firefox'
  const since = new Date(Date.now() - 30 * 864e5).toISOString()
  const url = `${NVD_BASE}?keywordSearch=${encodeURIComponent(keyword)}&resultsPerPage=20&pubStartDate=${since}`

  const headers: Record<string, string> = {}
  if (apiKey) headers['apiKey'] = apiKey

  const res = await fetch(url, { headers })
  if (!res.ok) throw new Error(`NVD search returned ${res.status}`)

  const data = await res.json()
  return (data.vulnerabilities ?? []).map(parseCveRecord)
}
```

Run: `pnpm test -- cve`
Expected: PASS

**Step 3: Commit**

```bash
git add monitoring/api/src/sources/cve.ts monitoring/api/src/sources/cve.test.ts
git commit -m "feat(monitoring): NVD CVE lookup and search"
```

---

## Task 5: GitHub Issues integration

**Files:**
- Create: `monitoring/api/src/github/issues.ts`
- Create: `monitoring/api/src/github/issues.test.ts`

**Step 1: Write the tests**

`monitoring/api/src/github/issues.test.ts`:
```typescript
import { parseMonitoringMetadata, buildIssueBody, buildIssueTitle } from './issues.js'
import type { MonitoringMetadata } from './issues.js'

const metadata: MonitoringMetadata = {
  engine: 'chromium',
  type: 'release',
  version: '125.0.6422.142',
  milestone: 125,
  releaseDate: '2026-03-28',
  deadline: '2026-04-12',
  cves: [{ id: 'CVE-2024-2996', severity: 'Critical', description: 'Use after free in WebAudio' }],
  upstreamUrl: 'https://chromereleases.googleblog.com/',
  branchName: 'engine-update/chromium-125.0.6422.142',
  prNumber: null,
  status: 'pending',
}

describe('buildIssueTitle', () => {
  it('formats a release issue title', () => {
    const title = buildIssueTitle(metadata)
    expect(title).toBe('[chromium] Release v125.0.6422.142')
  })

  it('formats a CVE issue title', () => {
    const cveMetadata: MonitoringMetadata = {
      ...metadata,
      type: 'cve',
      version: 'CVE-2024-2996',
    }
    const title = buildIssueTitle(cveMetadata)
    expect(title).toBe('[chromium] CVE-2024-2996 — Critical: Use after free in WebAudio')
  })
})

describe('parseMonitoringMetadata', () => {
  it('round-trips through buildIssueBody', () => {
    const body = buildIssueBody(metadata, 'Release notes here.')
    const parsed = parseMonitoringMetadata(body)
    expect(parsed).toMatchObject(metadata)
  })

  it('returns null for a body without the metadata block', () => {
    const parsed = parseMonitoringMetadata('Just a regular issue body')
    expect(parsed).toBeNull()
  })
})
```

Run: `pnpm test -- issues`
Expected: FAIL

**Step 2: Implement**

`monitoring/api/src/github/issues.ts`:
```typescript
import { Octokit } from '@octokit/rest'

export interface MonitoringMetadata {
  engine: 'chromium' | 'gecko'
  type: 'release' | 'cve'
  version: string
  milestone?: number
  releaseDate: string
  deadline: string
  cves: Array<{ id: string; severity: string; description: string }>
  upstreamUrl: string
  branchName: string
  prNumber: number | null
  status: 'pending' | 'pr-open' | 'pr-merged' | 'shipped' | 'dismissed'
}

const METADATA_START = '<!-- MONITORING_METADATA'
const METADATA_END = '-->'

export function buildIssueTitle(meta: MonitoringMetadata): string {
  if (meta.type === 'cve') {
    const severity = meta.cves[0]?.severity ?? 'Unknown'
    const desc = meta.cves[0]?.description ?? ''
    return `[${meta.engine}] ${meta.version} — ${severity}: ${desc}`
  }
  return `[${meta.engine}] Release v${meta.version}`
}

export function buildIssueBody(meta: MonitoringMetadata, summary: string): string {
  const cveList = meta.cves.length > 0
    ? meta.cves.map(c => `- ${c.id} (${c.severity}) — ${c.description}`).join('\n')
    : '_No CVEs listed for this release._'

  const prLink = meta.prNumber
    ? `[PR #${meta.prNumber}](https://github.com/${process.env.GITHUB_OWNER}/${process.env.GITHUB_REPO}/pull/${meta.prNumber})`
    : '_No PR yet_'

  const daysLeft = Math.ceil(
    (new Date(meta.deadline).getTime() - Date.now()) / 864e5
  )
  const deadlineNote = daysLeft > 0 ? `(${daysLeft} days remaining)` : `(OVERDUE by ${-daysLeft} days)`

  return `## Engine Update: ${meta.engine === 'chromium' ? 'Chromium' : 'Gecko/Firefox'} v${meta.version}

**Release Date:** ${meta.releaseDate}
**Deadline:** ${meta.deadline} ${deadlineNote}
**Status:** ${meta.status}

${summary}

### Security Fixes

${cveList}

### Links

- [Upstream release notes](${meta.upstreamUrl})
- PR: ${prLink}

---

${METADATA_START}
${JSON.stringify(meta, null, 2)}
${METADATA_END}`
}

export function parseMonitoringMetadata(body: string): MonitoringMetadata | null {
  const start = body.indexOf(METADATA_START)
  if (start === -1) return null

  const jsonStart = start + METADATA_START.length
  const end = body.indexOf(METADATA_END, jsonStart)
  if (end === -1) return null

  try {
    return JSON.parse(body.slice(jsonStart, end).trim())
  } catch {
    return null
  }
}

// GitHub API helpers

export async function searchIssues(
  octokit: Octokit,
  owner: string,
  repo: string,
  labels: string[],
  title?: string
): Promise<Array<{ number: number; title: string; body: string; labels: string[] }>> {
  const labelQuery = labels.map(l => `label:"${l}"`).join(' ')
  const titleQuery = title ? `"${title}" in:title` : ''
  const q = `repo:${owner}/${repo} is:issue ${labelQuery} ${titleQuery}`.trim()

  const res = await octokit.search.issuesAndPullRequests({ q, per_page: 20 })
  return res.data.items.map(item => ({
    number: item.number,
    title: item.title,
    body: item.body ?? '',
    labels: (item.labels as any[]).map(l => (typeof l === 'string' ? l : l.name ?? '')),
  }))
}

export async function createIssue(
  octokit: Octokit,
  owner: string,
  repo: string,
  title: string,
  body: string,
  labels: string[]
): Promise<number> {
  const res = await octokit.issues.create({ owner, repo, title, body, labels })
  return res.data.number
}

export async function updateIssue(
  octokit: Octokit,
  owner: string,
  repo: string,
  issueNumber: number,
  patch: { body?: string; labels?: string[]; state?: 'open' | 'closed' }
): Promise<void> {
  await octokit.issues.update({ owner, repo, issue_number: issueNumber, ...patch })
}

export async function addComment(
  octokit: Octokit,
  owner: string,
  repo: string,
  issueNumber: number,
  body: string
): Promise<void> {
  await octokit.issues.createComment({ owner, repo, issue_number: issueNumber, body })
}
```

Run: `pnpm test -- issues`
Expected: PASS

**Step 3: Commit**

```bash
git add monitoring/api/src/github/issues.ts monitoring/api/src/github/issues.test.ts
git commit -m "feat(monitoring): github issues CRUD with metadata block schema"
```

---

## Task 6: Branch convention + PR detection

**Files:**
- Create: `monitoring/api/src/github/branches.ts`
- Create: `monitoring/api/src/github/branches.test.ts`

**Step 1: Write tests**

`monitoring/api/src/github/branches.test.ts`:
```typescript
import { buildBranchName, parseBranchName, BRANCH_PATTERNS } from './branches.js'

describe('buildBranchName', () => {
  it('builds a release branch name', () => {
    expect(buildBranchName('chromium', 'release', '125.0.6422.142'))
      .toBe('engine-update/chromium-125.0.6422.142')
  })
  it('builds a CVE branch name', () => {
    expect(buildBranchName('gecko', 'cve', 'CVE-2024-2996'))
      .toBe('security/gecko-CVE-2024-2996')
  })
})

describe('parseBranchName', () => {
  it('parses a release branch', () => {
    const result = parseBranchName('engine-update/chromium-125.0.6422.142')
    expect(result).toEqual({ engine: 'chromium', type: 'release', version: '125.0.6422.142' })
  })
  it('parses a CVE branch', () => {
    const result = parseBranchName('security/gecko-CVE-2024-2996')
    expect(result).toEqual({ engine: 'gecko', type: 'cve', version: 'CVE-2024-2996' })
  })
  it('returns null for non-matching branches', () => {
    expect(parseBranchName('feature/some-random-feature')).toBeNull()
  })
})
```

**Step 2: Implement**

`monitoring/api/src/github/branches.ts`:
```typescript
import { Octokit } from '@octokit/rest'

export const BRANCH_PATTERNS = {
  release: /^engine-update\/(chromium|gecko)-([\d.]+)$/,
  cve:     /^security\/(chromium|gecko)-(CVE-\d{4}-\d+)$/,
}

export function buildBranchName(
  engine: 'chromium' | 'gecko',
  type: 'release' | 'cve',
  version: string
): string {
  return type === 'release'
    ? `engine-update/${engine}-${version}`
    : `security/${engine}-${version}`
}

export function parseBranchName(branch: string): {
  engine: 'chromium' | 'gecko'
  type: 'release' | 'cve'
  version: string
} | null {
  for (const [type, pattern] of Object.entries(BRANCH_PATTERNS)) {
    const m = branch.match(pattern)
    if (m) return { engine: m[1] as any, type: type as any, version: m[2] }
  }
  return null
}

export async function findPrForBranch(
  octokit: Octokit,
  owner: string,
  repo: string,
  branchName: string
): Promise<{ number: number; state: string; merged: boolean } | null> {
  const res = await octokit.pulls.list({
    owner,
    repo,
    head: `${owner}:${branchName}`,
    state: 'all',
    per_page: 5,
  })

  const pr = res.data[0]
  if (!pr) return null

  return {
    number: pr.number,
    state: pr.state,
    merged: !!pr.merged_at,
  }
}
```

Run: `pnpm test -- branches`
Expected: PASS

**Step 3: Commit**

```bash
git add monitoring/api/src/github/branches.ts monitoring/api/src/github/branches.test.ts
git commit -m "feat(monitoring): branch naming convention + PR detection"
```

---

## Task 7: Firecrawl wrapper

**Files:**
- Create: `monitoring/api/src/scraper.ts`
- Create: `monitoring/api/src/scraper.test.ts`

**Step 1: Write tests (against mock)**

`monitoring/api/src/scraper.test.ts`:
```typescript
import { extractCveIds, extractReleaseVersion } from './scraper.js'

describe('extractCveIds', () => {
  it('finds CVE IDs in markdown text', () => {
    const text = 'This release fixes CVE-2024-2996, CVE-2024-3156 and CVE-2024-3249.'
    expect(extractCveIds(text)).toEqual(['CVE-2024-2996', 'CVE-2024-3156', 'CVE-2024-3249'])
  })
  it('deduplicates repeated CVE IDs', () => {
    const text = 'CVE-2024-2996 mentioned twice. CVE-2024-2996 again.'
    expect(extractCveIds(text)).toEqual(['CVE-2024-2996'])
  })
  it('returns empty array when no CVEs found', () => {
    expect(extractCveIds('No vulnerabilities in this update.')).toEqual([])
  })
})

describe('extractReleaseVersion', () => {
  it('extracts a Chrome version number from text', () => {
    const text = 'Chrome 125 (125.0.6422.142) contains security updates.'
    expect(extractReleaseVersion('chromium', text)).toBe('125.0.6422.142')
  })
  it('extracts a Firefox version from text', () => {
    const text = 'Firefox 128.0 is now available'
    expect(extractReleaseVersion('gecko', text)).toBe('128.0')
  })
})
```

**Step 2: Implement**

`monitoring/api/src/scraper.ts`:
```typescript
import FirecrawlApp from '@mendable/firecrawl-js'

const CVE_PATTERN = /CVE-\d{4}-\d{4,}/g
const CHROMIUM_VERSION_PATTERN = /\b(\d{3,}\.0\.\d{4,}\.\d+)\b/
const GECKO_VERSION_PATTERN = /Firefox\s+(\d+\.\d+(?:\.\d+)?)/i

export function extractCveIds(text: string): string[] {
  return [...new Set(text.match(CVE_PATTERN) ?? [])]
}

export function extractReleaseVersion(engine: 'chromium' | 'gecko', text: string): string | null {
  const pattern = engine === 'chromium' ? CHROMIUM_VERSION_PATTERN : GECKO_VERSION_PATTERN
  return text.match(pattern)?.[1] ?? null
}

export async function scrapeReleaseNotes(url: string, apiKey: string): Promise<string> {
  const app = new FirecrawlApp({ apiKey })
  const result = await app.scrapeUrl(url, { formats: ['markdown'] })
  if (!result.success) throw new Error(`Firecrawl failed for ${url}: ${result.error}`)
  return result.markdown ?? ''
}

export async function scrapeAndExtractCves(url: string, apiKey: string): Promise<string[]> {
  const markdown = await scrapeReleaseNotes(url, apiKey)
  return extractCveIds(markdown)
}
```

Run: `pnpm test -- scraper`
Expected: PASS (unit tests only; Firecrawl calls are integration tests)

**Step 3: Commit**

```bash
git add monitoring/api/src/scraper.ts monitoring/api/src/scraper.test.ts
git commit -m "feat(monitoring): firecrawl wrapper with CVE ID extraction"
```

---

## Task 8: LLM Agent loop

**Files:**
- Create: `monitoring/api/src/agent/tools.ts`
- Create: `monitoring/api/src/agent/prompt.ts`
- Create: `monitoring/api/src/agent/loop.ts`

**Step 1: Define tool schemas**

`monitoring/api/src/agent/tools.ts`:
```typescript
import type { Octokit } from '@octokit/rest'
import type { ChatCompletionTool } from 'openai/resources/chat/completions'

import { fetchLatestChromiumRelease } from '../sources/chromium.js'
import { fetchLatestGeckoRelease } from '../sources/gecko.js'
import { fetchCve, searchRecentCves } from '../sources/cve.js'
import { searchIssues, createIssue, updateIssue, addComment, buildIssueTitle, buildIssueBody, parseMonitoringMetadata } from '../github/issues.js'
import { findPrForBranch, buildBranchName } from '../github/branches.js'
import { scrapeAndExtractCves, scrapeReleaseNotes } from '../scraper.js'

export const TOOL_SCHEMAS: ChatCompletionTool[] = [
  {
    type: 'function',
    function: {
      name: 'get_chromium_release',
      description: 'Fetch the latest stable Chromium release from Chromium Dash',
      parameters: { type: 'object', properties: {}, required: [] },
    },
  },
  {
    type: 'function',
    function: {
      name: 'get_gecko_release',
      description: 'Fetch the latest stable Firefox/Gecko release from Mozilla product-details',
      parameters: { type: 'object', properties: {}, required: [] },
    },
  },
  {
    type: 'function',
    function: {
      name: 'search_github_issues',
      description: 'Search GitHub Issues for existing monitoring records. Use labels like "engine:chromium,type:release" and an optional title substring.',
      parameters: {
        type: 'object',
        properties: {
          labels: { type: 'array', items: { type: 'string' }, description: 'Labels to filter by' },
          title: { type: 'string', description: 'Optional substring to match in issue title' },
        },
        required: ['labels'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'create_github_issue',
      description: 'Create a new monitoring issue for an engine release or CVE',
      parameters: {
        type: 'object',
        properties: {
          engine: { type: 'string', enum: ['chromium', 'gecko'] },
          type: { type: 'string', enum: ['release', 'cve'] },
          version: { type: 'string', description: 'Version string or CVE ID' },
          milestone: { type: 'number' },
          releaseDate: { type: 'string' },
          deadline: { type: 'string' },
          cves: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                id: { type: 'string' },
                severity: { type: 'string' },
                description: { type: 'string' },
              },
            },
          },
          upstreamUrl: { type: 'string' },
          summary: { type: 'string', description: 'Human-readable summary for the issue body' },
        },
        required: ['engine', 'type', 'version', 'releaseDate', 'deadline', 'upstreamUrl', 'summary'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'update_issue_status',
      description: 'Update the status of an existing monitoring issue',
      parameters: {
        type: 'object',
        properties: {
          issueNumber: { type: 'number' },
          status: { type: 'string', enum: ['pending', 'pr-open', 'pr-merged', 'shipped', 'dismissed'] },
          prNumber: { type: 'number' },
          comment: { type: 'string', description: 'Optional comment to add to the issue' },
        },
        required: ['issueNumber', 'status'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'get_pr_for_branch',
      description: 'Find a PR for a given branch name',
      parameters: {
        type: 'object',
        properties: {
          branchName: { type: 'string' },
        },
        required: ['branchName'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'scrape_release_notes',
      description: 'Scrape release notes from a URL using Firecrawl and extract CVE IDs',
      parameters: {
        type: 'object',
        properties: {
          url: { type: 'string' },
          extractCves: { type: 'boolean', default: true },
        },
        required: ['url'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'lookup_cve',
      description: 'Get full CVE details from the NVD API',
      parameters: {
        type: 'object',
        properties: {
          cveId: { type: 'string', description: 'e.g. CVE-2024-2996' },
        },
        required: ['cveId'],
      },
    },
  },
]

// Tool executor — maps tool names to implementations
export function createToolExecutor(deps: {
  octokit: Octokit
  owner: string
  repo: string
  firecrawlApiKey: string
  nvdApiKey?: string
}) {
  const { octokit, owner, repo, firecrawlApiKey, nvdApiKey } = deps

  return async function executeTool(name: string, args: any): Promise<string> {
    switch (name) {
      case 'get_chromium_release': {
        const release = await fetchLatestChromiumRelease()
        return JSON.stringify(release)
      }
      case 'get_gecko_release': {
        const release = await fetchLatestGeckoRelease()
        return JSON.stringify(release)
      }
      case 'search_github_issues': {
        const issues = await searchIssues(octokit, owner, repo, args.labels, args.title)
        return JSON.stringify(issues.map(i => ({
          number: i.number,
          title: i.title,
          labels: i.labels,
          metadata: parseMonitoringMetadata(i.body),
        })))
      }
      case 'create_github_issue': {
        const meta = {
          engine: args.engine,
          type: args.type,
          version: args.version,
          milestone: args.milestone,
          releaseDate: args.releaseDate,
          deadline: args.deadline,
          cves: args.cves ?? [],
          upstreamUrl: args.upstreamUrl,
          branchName: buildBranchName(args.engine, args.type, args.version),
          prNumber: null,
          status: 'pending' as const,
        }
        const title = buildIssueTitle(meta)
        const body = buildIssueBody(meta, args.summary)
        const labels = [
          `engine:${args.engine}`,
          `type:${args.type}`,
          'status:pending',
        ]
        const number = await createIssue(octokit, owner, repo, title, body, labels)
        return JSON.stringify({ created: true, issueNumber: number, title })
      }
      case 'update_issue_status': {
        const current = await octokit.issues.get({ owner, repo, issue_number: args.issueNumber })
        const meta = parseMonitoringMetadata(current.data.body ?? '')
        if (!meta) throw new Error(`Issue #${args.issueNumber} has no monitoring metadata`)

        const updated: typeof meta = { ...meta, status: args.status }
        if (args.prNumber != null) updated.prNumber = args.prNumber

        const statusLabels = ['status:pending', 'status:pr-open', 'status:pr-merged', 'status:shipped', 'status:dismissed']
        const currentLabels = (current.data.labels as any[])
          .map(l => typeof l === 'string' ? l : l.name ?? '')
          .filter(l => !statusLabels.includes(l))

        await updateIssue(octokit, owner, repo, args.issueNumber, {
          body: buildIssueBody(updated, '_Status updated by monitoring agent._'),
          labels: [...currentLabels, `status:${args.status}`],
        })

        if (args.comment) {
          await addComment(octokit, owner, repo, args.issueNumber, args.comment)
        }

        return JSON.stringify({ updated: true })
      }
      case 'get_pr_for_branch': {
        const pr = await findPrForBranch(octokit, owner, repo, args.branchName)
        return JSON.stringify(pr)
      }
      case 'scrape_release_notes': {
        if (args.extractCves !== false) {
          const cves = await scrapeAndExtractCves(args.url, firecrawlApiKey)
          return JSON.stringify({ cves, url: args.url })
        }
        const markdown = await scrapeReleaseNotes(args.url, firecrawlApiKey)
        return JSON.stringify({ markdown: markdown.slice(0, 4000) })  // truncate
      }
      case 'lookup_cve': {
        const cve = await fetchCve(args.cveId, nvdApiKey)
        return JSON.stringify(cve)
      }
      default:
        throw new Error(`Unknown tool: ${name}`)
    }
  }
}
```

**Step 2: Write the system prompt**

`monitoring/api/src/agent/prompt.ts`:
```typescript
export const SYSTEM_PROMPT = `You are the Kelpie Engine Monitoring Agent.

Your job is to ensure that the Kelpie browser app stays up-to-date with Chromium and Gecko engine releases to comply with Apple's App Review requirements (15-day update rule, 30-day critical CVE rule).

You run on a schedule every 2 hours. Each run, you:

1. Fetch the latest stable Chromium and Gecko releases.
2. For each engine, search GitHub Issues using label "engine:{engine}" + "type:release" to see if a tracking issue exists for that version.
3. If no issue exists, scrape the release notes URL to extract CVE IDs, look up their details, then create a GitHub Issue with full metadata.
4. If an issue exists, check if a PR exists for the branch named "engine-update/{engine}-{version}". Update the issue status accordingly.
5. Also search NVD for recent CVEs and create individual CVE issues for Critical/High severity items not yet tracked.

Rules:
- Never create duplicate issues. Always search first.
- A "pending" issue has no PR yet.
- A "pr-open" issue has an open PR on the correct branch.
- A "pr-merged" issue has a merged PR but is not yet in App Store.
- A "shipped" issue has been released to App Store.
- For critical CVEs (CVSS 9+), add a note that the 30-day rule applies.
- Keep issue bodies factual and concise.
- When in doubt, add a comment to the existing issue rather than creating a new one.

Be efficient. Do not re-fetch the same data multiple times in one run. If you cannot determine something, leave the issue unchanged and stop.`
```

**Step 3: Write the agent loop**

`monitoring/api/src/agent/loop.ts`:
```typescript
import OpenAI from 'openai'
import type { ChatCompletionMessageParam } from 'openai/resources/chat/completions'
import { TOOL_SCHEMAS, createToolExecutor } from './tools.js'
import { SYSTEM_PROMPT } from './prompt.js'
import type { Octokit } from '@octokit/rest'

export interface AgentDeps {
  octokit: Octokit
  owner: string
  repo: string
  firecrawlApiKey: string
  nvdApiKey?: string
  llmApiKey: string
  llmBaseUrl: string
  llmModel: string
}

export interface RunResult {
  success: boolean
  toolCallCount: number
  error?: string
}

export async function runMonitoringAgent(deps: AgentDeps): Promise<RunResult> {
  const client = new OpenAI({ apiKey: deps.llmApiKey, baseURL: deps.llmBaseUrl })
  const executeTool = createToolExecutor(deps)

  const messages: ChatCompletionMessageParam[] = [
    { role: 'system', content: SYSTEM_PROMPT },
    { role: 'user', content: 'Run your monitoring cycle now. Check both Chromium and Gecko. Report what you found and what actions you took.' },
  ]

  let toolCallCount = 0
  const MAX_ITERATIONS = 30  // guard against infinite loops

  for (let i = 0; i < MAX_ITERATIONS; i++) {
    const response = await client.chat.completions.create({
      model: deps.llmModel,
      messages,
      tools: TOOL_SCHEMAS,
      tool_choice: 'auto',
    })

    const choice = response.choices[0]
    messages.push({ role: 'assistant', ...choice.message })

    if (choice.finish_reason === 'stop' || !choice.message.tool_calls?.length) {
      console.log('[agent] Done.', choice.message.content)
      return { success: true, toolCallCount }
    }

    // Execute all tool calls in parallel
    const results = await Promise.all(
      choice.message.tool_calls.map(async tc => {
        toolCallCount++
        try {
          const args = JSON.parse(tc.function.arguments)
          console.log(`[tool] ${tc.function.name}`, args)
          const result = await executeTool(tc.function.name, args)
          return { tool_call_id: tc.id, role: 'tool' as const, content: result }
        } catch (err: any) {
          console.error(`[tool] ${tc.function.name} failed:`, err.message)
          return { tool_call_id: tc.id, role: 'tool' as const, content: `Error: ${err.message}` }
        }
      })
    )

    messages.push(...results)
  }

  return { success: false, toolCallCount, error: 'Max iterations reached' }
}
```

**Step 4: Commit**

```bash
git add monitoring/api/src/agent/
git commit -m "feat(monitoring): LLM agent loop with tool calling (Minimax 2.7 compatible)"
```

---

## Task 9: Monitoring API server

**Files:**
- Create: `monitoring/api/src/server.ts`
- Create: `monitoring/api/src/index.ts`

**Step 1: Implement the server**

`monitoring/api/src/server.ts`:
```typescript
import { Hono } from 'hono'
import { Octokit } from '@octokit/rest'
import { searchIssues, parseMonitoringMetadata } from './github/issues.js'
import { seedLabels } from './github/labels.js'
import { runMonitoringAgent } from './agent/loop.js'
import type { AgentDeps } from './agent/loop.js'

export function createServer(deps: AgentDeps & { owner: string; repo: string }) {
  const app = new Hono()

  app.get('/api/v1/health', c => c.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    owner: deps.owner,
    repo: deps.repo,
  }))

  app.get('/api/v1/status', async c => {
    const issues = await searchIssues(deps.octokit, deps.owner, deps.repo, [], '')

    const records = issues
      .map(i => ({ ...parseMonitoringMetadata(i.body), issueNumber: i.number, title: i.title }))
      .filter(Boolean)

    return c.json({ issues: records, fetchedAt: new Date().toISOString() })
  })

  app.post('/api/v1/check', async c => {
    const result = await runMonitoringAgent(deps)
    return c.json(result)
  })

  app.post('/api/v1/seed-labels', async c => {
    await seedLabels(deps.octokit, deps.owner, deps.repo)
    return c.json({ seeded: true })
  })

  return app
}
```

`monitoring/api/src/index.ts`:
```typescript
import { serve } from '@hono/node-server'
import { Octokit } from '@octokit/rest'
import cron from 'node-cron'
import { createServer } from './server.js'
import { runMonitoringAgent } from './agent/loop.js'

const {
  GITHUB_TOKEN,
  GITHUB_OWNER = 'UnlikeOtherAI',
  GITHUB_REPO = 'kelpie',
  MINIMAX_API_KEY,
  MINIMAX_BASE_URL = 'https://api.minimax.chat/v1',
  MINIMAX_MODEL = 'minimax-text-01',
  FIRECRAWL_API_KEY = '',
  NVD_API_KEY,
  PORT = '3001',
  SCAN_CRON = '0 */2 * * *',
} = process.env

if (!GITHUB_TOKEN) throw new Error('GITHUB_TOKEN is required')
if (!MINIMAX_API_KEY) throw new Error('MINIMAX_API_KEY is required')

const octokit = new Octokit({ auth: GITHUB_TOKEN })
const deps = {
  octokit,
  owner: GITHUB_OWNER,
  repo: GITHUB_REPO,
  firecrawlApiKey: FIRECRAWL_API_KEY,
  nvdApiKey: NVD_API_KEY,
  llmApiKey: MINIMAX_API_KEY,
  llmBaseUrl: MINIMAX_BASE_URL,
  llmModel: MINIMAX_MODEL,
}

const app = createServer(deps)

cron.schedule(SCAN_CRON, async () => {
  console.log('[cron] Starting monitoring scan...')
  const result = await runMonitoringAgent(deps)
  console.log('[cron] Scan complete:', result)
})

serve({ fetch: app.fetch, port: Number(PORT) }, () => {
  console.log(`Monitoring API running on http://localhost:${PORT}`)
  console.log(`Next scan: ${SCAN_CRON}`)
})
```

**Step 2: Commit**

```bash
git add monitoring/api/src/server.ts monitoring/api/src/index.ts
git commit -m "feat(monitoring): hono API server with cron scheduler"
```

---

## Task 10: Frontend dashboard

**Files:**
- Create: `monitoring/frontend/index.html`
- Create: `monitoring/frontend/src/main.tsx`
- Create: `monitoring/frontend/src/App.tsx`
- Create: `monitoring/frontend/src/components/EngineCard.tsx`
- Create: `monitoring/frontend/src/components/IssueList.tsx`

**Step 1: Create the HTML entry**

`monitoring/frontend/index.html`:
```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Kelpie Engine Monitor</title>
    <style>
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body { font-family: system-ui, sans-serif; background: #0d1117; color: #e6edf3; min-height: 100vh; }
    </style>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

**Step 2: Create root + App**

`monitoring/frontend/src/main.tsx`:
```tsx
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { App } from './App'

createRoot(document.getElementById('root')!).render(
  <StrictMode><App /></StrictMode>
)
```

`monitoring/frontend/src/App.tsx`:
```tsx
import { useEffect, useState } from 'react'
import { EngineCard } from './components/EngineCard'
import { IssueList } from './components/IssueList'

type MonitoringMetadata = {
  engine: 'chromium' | 'gecko'
  type: 'release' | 'cve'
  version: string
  releaseDate: string
  deadline: string
  status: string
  prNumber: number | null
  cves: Array<{ id: string; severity: string; description: string }>
  issueNumber: number
  title: string
}

const ENGINE_NAMES = { chromium: 'Chromium', gecko: 'Gecko / Firefox' }

export function App() {
  const [data, setData] = useState<MonitoringMetadata[]>([])
  const [lastFetch, setLastFetch] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    async function load() {
      try {
        const res = await fetch('/api/v1/status')
        if (!res.ok) throw new Error(`API returned ${res.status}`)
        const json = await res.json()
        setData(json.issues ?? [])
        setLastFetch(json.fetchedAt)
        setError(null)
      } catch (e: any) {
        setError(e.message)
      }
    }
    load()
    const id = setInterval(load, 60_000)
    return () => clearInterval(id)
  }, [])

  const releases = data.filter(d => d.type === 'release')
  const cves = data.filter(d => d.type === 'cve')

  return (
    <div style={{ maxWidth: 1100, margin: '0 auto', padding: '32px 16px' }}>
      <h1 style={{ fontSize: 24, fontWeight: 700, marginBottom: 8 }}>
        Kelpie Engine Monitor
      </h1>
      {lastFetch && (
        <p style={{ color: '#8b949e', fontSize: 13, marginBottom: 32 }}>
          Last fetched: {new Date(lastFetch).toLocaleString()}
        </p>
      )}
      {error && (
        <div style={{ background: '#3d1c1c', border: '1px solid #f85149', borderRadius: 8, padding: 16, marginBottom: 24 }}>
          API error: {error}
        </div>
      )}
      <section style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, marginBottom: 32 }}>
        {(['chromium', 'gecko'] as const).map(engine => {
          const latest = releases.find(r => r.engine === engine)
          return <EngineCard key={engine} engine={engine} name={ENGINE_NAMES[engine]} release={latest ?? null} />
        })}
      </section>
      <IssueList title="Open Releases" items={releases} />
      <IssueList title="CVE Tracking" items={cves} />
    </div>
  )
}
```

**Step 3: Components**

`monitoring/frontend/src/components/EngineCard.tsx`:
```tsx
type Release = { version: string; status: string; deadline: string; prNumber: number | null; issueNumber: number } | null

const STATUS_COLOR: Record<string, string> = {
  pending: '#8b949e',
  'pr-open': '#388bfd',
  'pr-merged': '#8957e5',
  shipped: '#3fb950',
  dismissed: '#6e7681',
}

export function EngineCard({ engine, name, release }: { engine: string; name: string; release: Release }) {
  const status = release?.status ?? 'unknown'
  const color = STATUS_COLOR[status] ?? '#8b949e'

  const daysLeft = release
    ? Math.ceil((new Date(release.deadline).getTime() - Date.now()) / 864e5)
    : null

  return (
    <div style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: 10, padding: 20 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
        <h2 style={{ fontSize: 16, fontWeight: 600 }}>{name}</h2>
        <span style={{ fontSize: 12, color, fontWeight: 600, textTransform: 'uppercase', letterSpacing: 1 }}>
          {status}
        </span>
      </div>
      {release ? (
        <>
          <p style={{ fontSize: 22, fontWeight: 700, fontFamily: 'monospace', marginBottom: 4 }}>
            v{release.version}
          </p>
          <p style={{ fontSize: 12, color: '#8b949e' }}>
            Deadline: {release.deadline}
            {daysLeft !== null && (
              <span style={{ color: daysLeft < 5 ? '#f85149' : '#8b949e', marginLeft: 8 }}>
                ({daysLeft > 0 ? `${daysLeft}d left` : 'OVERDUE'})
              </span>
            )}
          </p>
          {release.prNumber && (
            <p style={{ fontSize: 12, color: '#388bfd', marginTop: 6 }}>PR #{release.prNumber}</p>
          )}
        </>
      ) : (
        <p style={{ color: '#8b949e', fontSize: 14 }}>No release tracked yet</p>
      )}
    </div>
  )
}
```

`monitoring/frontend/src/components/IssueList.tsx`:
```tsx
type Issue = {
  issueNumber: number
  title: string
  engine: string
  status: string
  deadline: string
  cves: Array<{ id: string; severity: string }>
}

const SEVERITY_COLOR: Record<string, string> = {
  Critical: '#f85149',
  High: '#d29922',
  Medium: '#e3b341',
  Low: '#3fb950',
}

export function IssueList({ title, items }: { title: string; items: Issue[] }) {
  if (!items.length) return null

  return (
    <section style={{ marginBottom: 32 }}>
      <h2 style={{ fontSize: 16, fontWeight: 600, marginBottom: 12, color: '#8b949e' }}>{title}</h2>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {items.map(item => (
          <div key={item.issueNumber} style={{ background: '#161b22', border: '1px solid #30363d', borderRadius: 8, padding: 16 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
              <span style={{ fontSize: 14, fontWeight: 500 }}>#{item.issueNumber} {item.title}</span>
              <span style={{ fontSize: 11, color: '#8b949e', marginLeft: 16, whiteSpace: 'nowrap' }}>
                {item.status}
              </span>
            </div>
            {item.cves?.length > 0 && (
              <div style={{ marginTop: 8, display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                {item.cves.map(cve => (
                  <span key={cve.id} style={{
                    fontSize: 11,
                    background: `${SEVERITY_COLOR[cve.severity] ?? '#8b949e'}22`,
                    color: SEVERITY_COLOR[cve.severity] ?? '#8b949e',
                    border: `1px solid ${SEVERITY_COLOR[cve.severity] ?? '#8b949e'}44`,
                    borderRadius: 4,
                    padding: '2px 6px',
                  }}>
                    {cve.id} ({cve.severity})
                  </span>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>
    </section>
  )
}
```

**Step 4: Commit**

```bash
git add monitoring/frontend/
git commit -m "feat(monitoring): React dashboard with engine status cards and issue list"
```

---

## Task 11: Bootstrap script

**Files:**
- Create: `monitoring/api/src/bootstrap.ts`

This is a one-time script to seed labels and run the first scan.

```typescript
import { Octokit } from '@octokit/rest'
import { seedLabels } from './github/labels.js'
import { runMonitoringAgent } from './agent/loop.js'

const octokit = new Octokit({ auth: process.env.GITHUB_TOKEN })

console.log('Seeding labels...')
await seedLabels(octokit, process.env.GITHUB_OWNER!, process.env.GITHUB_REPO!)
console.log('Labels seeded.')

console.log('Running initial scan...')
const result = await runMonitoringAgent({
  octokit,
  owner: process.env.GITHUB_OWNER!,
  repo: process.env.GITHUB_REPO!,
  firecrawlApiKey: process.env.FIRECRAWL_API_KEY!,
  nvdApiKey: process.env.NVD_API_KEY,
  llmApiKey: process.env.MINIMAX_API_KEY!,
  llmBaseUrl: process.env.MINIMAX_BASE_URL!,
  llmModel: process.env.MINIMAX_MODEL!,
})

console.log('Initial scan result:', result)
```

**Step 5: Final commit**

```bash
git add monitoring/api/src/bootstrap.ts
git commit -m "feat(monitoring): bootstrap script for first run + label seeding"
```

---

## Quick Start

After implementing:

```bash
# 1. Set environment variables
cp monitoring/.env.example monitoring/.env
# Edit monitoring/.env with real credentials

# 2. Install deps
cd monitoring/api && pnpm install
cd ../frontend && pnpm install

# 3. Seed labels and run first scan
cd api && FIRECRAWL_API_KEY=... GITHUB_TOKEN=... MINIMAX_API_KEY=... tsx src/bootstrap.ts

# 4. Start API (dev)
pnpm dev

# 5. Start frontend (separate terminal)
cd ../frontend && pnpm dev
```

---

## What GitHub Issues Look Like

After the first scan, the repo will have issues like:

```
[chromium] Release v125.0.6422.142      (labels: engine:chromium, type:release, status:pending)
[gecko] Release v128.0                  (labels: engine:gecko, type:release, status:shipped)
[chromium] CVE-2024-2996 — Critical: … (labels: engine:chromium, type:cve, priority:critical, status:pending)
```

No external database. The full state is in GitHub. The agent can be stopped, restarted, or swapped for a different LLM without losing history.
