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
