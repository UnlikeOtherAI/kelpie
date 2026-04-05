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
  FIRECRAWL_API_KEY,
  NVD_API_KEY,
  PORT = '3001',
  SCAN_CRON = '0 */2 * * *',
} = process.env

if (!GITHUB_TOKEN) throw new Error('GITHUB_TOKEN is required')
if (!MINIMAX_API_KEY) throw new Error('MINIMAX_API_KEY is required')
if (!FIRECRAWL_API_KEY) throw new Error('FIRECRAWL_API_KEY is required')

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

cron.schedule(SCAN_CRON, () => {
  console.log('[cron] Starting monitoring scan...')
  runMonitoringAgent(deps)
    .then(result => console.log('[cron] Scan complete:', result))
    .catch(err => console.error('[cron] Scan failed:', err))
})

serve({ fetch: app.fetch, port: Number(PORT) }, () => {
  console.log(`Monitoring API running on http://localhost:${PORT}`)
  console.log(`Next scan: ${SCAN_CRON}`)
})
