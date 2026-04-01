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
    expect(parsed).toEqual(metadata)
  })

  it('returns null for a body without the metadata block', () => {
    const parsed = parseMonitoringMetadata('Just a regular issue body')
    expect(parsed).toBeNull()
  })
})
