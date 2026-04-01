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
  const isAnthropic = deps.llmBaseUrl.includes('anthropic.com')
  const client = new OpenAI({
    apiKey: deps.llmApiKey,
    baseURL: deps.llmBaseUrl,
    defaultHeaders: isAnthropic ? { 'anthropic-version': '2023-06-01' } : undefined,
  })
  const executeTool = createToolExecutor(deps)

  const messages: ChatCompletionMessageParam[] = [
    { role: 'system', content: SYSTEM_PROMPT },
    { role: 'user', content: 'Run your monitoring cycle now. Check both Chromium and Gecko. Report what you found and what actions you took.' },
  ]

  let toolCallCount = 0
  const MAX_ITERATIONS = 30

  for (let i = 0; i < MAX_ITERATIONS; i++) {
    const response = await client.chat.completions.create({
      model: deps.llmModel,
      messages,
      tools: TOOL_SCHEMAS,
      tool_choice: 'auto',
    })

    const choice = response.choices[0]
    messages.push(choice.message)

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
