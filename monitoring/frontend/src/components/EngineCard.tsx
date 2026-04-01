import type { MonitoringMetadata } from '../App.js'

const STATUS_COLORS: Record<MonitoringMetadata['status'], string> = {
  pending: '#8b949e',
  'pr-open': '#388bfd',
  'pr-merged': '#8957e5',
  shipped: '#3fb950',
  dismissed: '#6e7681',
}

const STATUS_LABELS: Record<MonitoringMetadata['status'], string> = {
  pending: 'Pending',
  'pr-open': 'PR Open',
  'pr-merged': 'PR Merged',
  shipped: 'Shipped',
  dismissed: 'Dismissed',
}

function engineDisplayName(engine: string): string {
  if (engine === 'chromium') return 'Chromium'
  if (engine === 'gecko') return 'Gecko / Firefox'
  return engine.charAt(0).toUpperCase() + engine.slice(1)
}

function daysRemaining(deadline: string): number {
  const now = new Date()
  const due = new Date(deadline)
  const diff = due.getTime() - now.getTime()
  return Math.floor(diff / (1000 * 60 * 60 * 24))
}

interface Props {
  issue: MonitoringMetadata
}

export function EngineCard({ issue }: Props) {
  const statusColor = STATUS_COLORS[issue.status]
  const statusLabel = STATUS_LABELS[issue.status]

  let deadlineNode: React.ReactNode = null
  if (issue.deadline) {
    const days = daysRemaining(issue.deadline)
    const deadlineDate = new Date(issue.deadline).toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    })
    let daysLabel: React.ReactNode
    if (days < 0) {
      daysLabel = (
        <span style={{ color: '#f85149', fontWeight: 600 }}>
          {' '}OVERDUE
        </span>
      )
    } else if (days < 5) {
      daysLabel = (
        <span style={{ color: '#f85149', fontWeight: 600 }}>
          {' '}({days} day{days !== 1 ? 's' : ''} remaining)
        </span>
      )
    } else {
      daysLabel = (
        <span style={{ color: '#8b949e' }}>
          {' '}({days} day{days !== 1 ? 's' : ''} remaining)
        </span>
      )
    }
    deadlineNode = (
      <p style={{ fontSize: 13, color: '#8b949e', marginTop: 8 }}>
        Deadline: <span style={{ color: '#e6edf3' }}>{deadlineDate}</span>
        {daysLabel}
      </p>
    )
  }

  return (
    <div
      style={{
        background: '#161b22',
        border: '1px solid #30363d',
        borderRadius: 8,
        padding: 20,
      }}
    >
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 12 }}>
        <h3 style={{ fontSize: 16, fontWeight: 600, color: '#e6edf3' }}>
          {engineDisplayName(issue.engine)}
        </h3>
        <span
          style={{
            fontSize: 12,
            fontWeight: 600,
            color: statusColor,
            background: `${statusColor}1a`,
            border: `1px solid ${statusColor}4d`,
            borderRadius: 12,
            padding: '2px 10px',
          }}
        >
          {statusLabel}
        </span>
      </div>

      <p
        style={{
          fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
          fontSize: 28,
          fontWeight: 700,
          color: '#e6edf3',
          letterSpacing: '-0.5px',
          marginBottom: 4,
        }}
      >
        {issue.version}
      </p>

      {deadlineNode}

      {issue.prNumber && (
        <p style={{ fontSize: 13, marginTop: 8 }}>
          <a
            href={`https://github.com/unlikeotherai/mollotov/pull/${issue.prNumber}`}
            target="_blank"
            rel="noopener noreferrer"
            style={{ color: '#388bfd', textDecoration: 'none' }}
          >
            PR #{issue.prNumber}
          </a>
        </p>
      )}
    </div>
  )
}
