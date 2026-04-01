import type { Octokit } from '@octokit/rest'
import type { ChatCompletionTool } from 'openai/resources/chat/completions'

import { fetchLatestChromiumRelease } from '../sources/chromium.js'
import { fetchLatestGeckoRelease } from '../sources/gecko.js'
import { fetchCve } from '../sources/cve.js'
import {
  searchIssues,
  createIssue,
  updateIssue,
  addComment,
  buildIssueTitle,
  buildIssueBody,
  parseMonitoringMetadata,
} from '../github/issues.js'
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

export function createToolExecutor(deps: {
  octokit: Octokit
  owner: string
  repo: string
  firecrawlApiKey: string
  nvdApiKey?: string
}) {
  const { octokit, owner, repo, firecrawlApiKey, nvdApiKey } = deps

  return async function executeTool(name: string, args: Record<string, any>): Promise<string> {
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
        const issues = await searchIssues(octokit, owner, repo, args['labels'] as string[], args['title'] as string | undefined)
        return JSON.stringify(issues.map(i => ({
          number: i.number,
          title: i.title,
          labels: i.labels,
          metadata: parseMonitoringMetadata(i.body),
        })))
      }
      case 'create_github_issue': {
        const meta = {
          engine: args['engine'] as 'chromium' | 'gecko',
          type: args['type'] as 'release' | 'cve',
          version: args['version'] as string,
          milestone: args['milestone'] as number | undefined,
          releaseDate: args['releaseDate'] as string,
          deadline: args['deadline'] as string,
          cves: (args['cves'] ?? []) as Array<{ id: string; severity: string; description: string }>,
          upstreamUrl: args['upstreamUrl'] as string,
          branchName: buildBranchName(args['engine'] as 'chromium' | 'gecko', args['type'] as 'release' | 'cve', args['version'] as string),
          prNumber: null,
          status: 'pending' as const,
        }
        const title = buildIssueTitle(meta)
        const body = buildIssueBody(meta, args['summary'] as string)
        const labels = [
          `engine:${args['engine']}`,
          `type:${args['type']}`,
          'status:pending',
        ]
        const number = await createIssue(octokit, owner, repo, title, body, labels)
        return JSON.stringify({ created: true, issueNumber: number, title })
      }
      case 'update_issue_status': {
        const current = await octokit.issues.get({ owner, repo, issue_number: args['issueNumber'] as number })
        const meta = parseMonitoringMetadata(current.data.body ?? '')
        if (!meta) throw new Error(`Issue #${args['issueNumber']} has no monitoring metadata`)

        const updated = { ...meta, status: args['status'] as typeof meta.status }
        if (args['prNumber'] != null) updated.prNumber = args['prNumber'] as number

        const STATUS_LABELS = ['status:pending', 'status:pr-open', 'status:pr-merged', 'status:shipped', 'status:dismissed']
        const currentLabels = (current.data.labels as Array<string | { name?: string }>)
          .map(l => (typeof l === 'string' ? l : l.name ?? ''))
          .filter(l => !STATUS_LABELS.includes(l))

        const summary = meta.summary ?? '_Status updated by monitoring agent._'
        await updateIssue(octokit, owner, repo, args['issueNumber'] as number, {
          body: buildIssueBody(updated, summary),
          labels: [...currentLabels, `status:${args['status']}`],
        })

        if (args['comment']) {
          await addComment(octokit, owner, repo, args['issueNumber'] as number, args['comment'] as string)
        }

        return JSON.stringify({ updated: true })
      }
      case 'get_pr_for_branch': {
        const pr = await findPrForBranch(octokit, owner, repo, args['branchName'] as string)
        return JSON.stringify(pr)
      }
      case 'scrape_release_notes': {
        if (args['extractCves'] !== false) {
          const cves = await scrapeAndExtractCves(args['url'] as string, firecrawlApiKey)
          return JSON.stringify({ cves, url: args['url'] })
        }
        const markdown = await scrapeReleaseNotes(args['url'] as string, firecrawlApiKey)
        return JSON.stringify({ markdown: markdown.slice(0, 4000) })
      }
      case 'lookup_cve': {
        const cve = await fetchCve(args['cveId'] as string, nvdApiKey)
        return JSON.stringify(cve)
      }
      default:
        throw new Error(`Unknown tool: ${name}`)
    }
  }
}
