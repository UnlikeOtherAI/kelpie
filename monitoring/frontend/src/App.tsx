import { useState, useEffect } from 'react'
import { EngineCard } from './components/EngineCard.js'
import { IssueList } from './components/IssueList.js'

export interface MonitoringMetadata {
  engine: string
  type: 'release' | 'cve'
  version: string
  status: 'pending' | 'pr-open' | 'pr-merged' | 'shipped' | 'dismissed'
  deadline: string | null
  prNumber: number | null
  cves: Array<{ id: string; severity: 'Critical' | 'High' | 'Medium' | 'Low' }>
  issueNumber: number
  title: string
}

interface ApiResponse {
  issues: MonitoringMetadata[]
}

export function App() {
  const [data, setData] = useState<ApiResponse | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [lastFetched, setLastFetched] = useState<Date | null>(null)

  async function fetchStatus() {
    try {
      const res = await fetch('/api/v1/status')
      if (!res.ok) throw new Error(`HTTP ${res.status}: ${res.statusText}`)
      const json = (await res.json()) as ApiResponse
      setData(json)
      setLastFetched(new Date())
      setError(null)
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err))
    }
  }

  useEffect(() => {
    void fetchStatus()
    const interval = setInterval(() => void fetchStatus(), 60_000)
    return () => clearInterval(interval)
  }, [])

  const releases = data?.issues.filter((i) => i.type === 'release') ?? []
  const cves = data?.issues.filter((i) => i.type === 'cve') ?? []

  const chromiumEngine = releases.find((i) => i.engine === 'chromium')
  const geckoEngine = releases.find((i) => i.engine === 'gecko')

  return (
    <div style={{ maxWidth: 960, margin: '0 auto', padding: '32px 16px' }}>
      <header style={{ marginBottom: 32 }}>
        <h1 style={{ fontSize: 24, fontWeight: 600, color: '#e6edf3', marginBottom: 8 }}>
          Kelpie Engine Monitor
        </h1>
        {lastFetched && (
          <p style={{ fontSize: 13, color: '#8b949e' }}>
            Last fetched: {lastFetched.toLocaleTimeString()}
          </p>
        )}
      </header>

      {error && (
        <div
          style={{
            background: '#21070a',
            border: '1px solid #f85149',
            borderRadius: 6,
            padding: '12px 16px',
            marginBottom: 24,
            color: '#f85149',
            fontSize: 14,
          }}
        >
          Failed to fetch status: {error}
        </div>
      )}

      <section style={{ marginBottom: 32 }}>
        <h2 style={{ fontSize: 16, fontWeight: 600, color: '#8b949e', marginBottom: 16, textTransform: 'uppercase', letterSpacing: '0.05em' }}>
          Engine Status
        </h2>
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
            gap: 16,
          }}
        >
          {chromiumEngine ? (
            <EngineCard issue={chromiumEngine} />
          ) : (
            <EngineCard
              issue={{
                engine: 'chromium',
                type: 'release',
                version: '—',
                status: 'pending',
                deadline: null,
                prNumber: null,
                cves: [],
                issueNumber: 0,
                title: 'Chromium',
              }}
            />
          )}
          {geckoEngine ? (
            <EngineCard issue={geckoEngine} />
          ) : (
            <EngineCard
              issue={{
                engine: 'gecko',
                type: 'release',
                version: '—',
                status: 'pending',
                deadline: null,
                prNumber: null,
                cves: [],
                issueNumber: 0,
                title: 'Gecko / Firefox',
              }}
            />
          )}
        </div>
      </section>

      {releases.length > 0 && (
        <section style={{ marginBottom: 32 }}>
          <h2 style={{ fontSize: 16, fontWeight: 600, color: '#8b949e', marginBottom: 16, textTransform: 'uppercase', letterSpacing: '0.05em' }}>
            Release Tracking
          </h2>
          <IssueList issues={releases} />
        </section>
      )}

      {cves.length > 0 && (
        <section style={{ marginBottom: 32 }}>
          <h2 style={{ fontSize: 16, fontWeight: 600, color: '#8b949e', marginBottom: 16, textTransform: 'uppercase', letterSpacing: '0.05em' }}>
            CVE Tracking
          </h2>
          <IssueList issues={cves} />
        </section>
      )}

      {!data && !error && (
        <p style={{ color: '#8b949e', textAlign: 'center', padding: 48 }}>Loading…</p>
      )}
    </div>
  )
}
