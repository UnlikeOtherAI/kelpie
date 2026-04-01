import { Octokit } from '@octokit/rest'

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
