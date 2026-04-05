import { Octokit } from '@octokit/rest'
import { seedLabels } from './github/labels.js'
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
} = process.env

if (!GITHUB_TOKEN) throw new Error('GITHUB_TOKEN is required')
if (!MINIMAX_API_KEY) throw new Error('MINIMAX_API_KEY is required')
if (!FIRECRAWL_API_KEY) throw new Error('FIRECRAWL_API_KEY is required')

const octokit = new Octokit({ auth: GITHUB_TOKEN })

console.log('Seeding labels...')
await seedLabels(octokit, GITHUB_OWNER, GITHUB_REPO)
console.log('Labels seeded.')

console.log('Running initial scan...')
const result = await runMonitoringAgent({
  octokit,
  owner: GITHUB_OWNER,
  repo: GITHUB_REPO,
  firecrawlApiKey: FIRECRAWL_API_KEY,
  nvdApiKey: NVD_API_KEY,
  llmApiKey: MINIMAX_API_KEY,
  llmBaseUrl: MINIMAX_BASE_URL,
  llmModel: MINIMAX_MODEL,
})

console.log('Initial scan result:', result)
