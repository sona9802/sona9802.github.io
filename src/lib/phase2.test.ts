import { describe, expect, it } from 'vitest'
import { invitationTokenFromLocation, normalizeCount } from './phase2'

describe('Phase 2 form helpers', () => {
  it('normalizes family counts to safe integer limits', () => {
    expect(normalizeCount('3.8', 10)).toBe(3)
    expect(normalizeCount('-2', 10)).toBe(0)
    expect(normalizeCount('40', 10)).toBe(10)
  })

  it('reads an invitation token without accepting unrelated parameters', () => {
    expect(invitationTokenFromLocation('?invite=abc123&utm_source=email')).toBe('abc123')
    expect(invitationTokenFromLocation('?other=abc123')).toBe('')
  })
})
