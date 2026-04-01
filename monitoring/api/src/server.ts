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
      .map(i => {
        const meta = parseMonitoringMetadata(i.body)
        if (!meta) return null
        return { ...meta, issueNumber: i.number, title: i.title }
      })
      .filter((r): r is NonNullable<typeof r> => r !== null)
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

  app.onError((err, c) => {
    console.error('[server] Route error:', err)
    return c.json({ error: err.message }, 500)
  })

  return app
}
