import { describe, expect, it } from 'vitest'
import { buildAuthRedirectUrl, buildInvitationEmailHref, invitationTokenFromLocation, normalizeCount } from './phase2'

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

  it('keeps the invitation in the auth callback without using the session fragment', () => {
    expect(buildAuthRedirectUrl('https://sona9802.github.io', '/', 'invite-token')).toBe(
      'https://sona9802.github.io/?invite=invite-token',
    )
  })

  it('builds an invitation email with the full secure link and clear code instructions', () => {
    const href = buildInvitationEmailHref('member@example.test', 'Batch Mate', 'https://example.test/?invite=abc#member-portal')
    expect(href).toContain('mailto:member%40example.test')
    expect(decodeURIComponent(href)).toContain('Invitation code: You do not need to copy a separate code.')
    expect(decodeURIComponent(href)).toContain('No username or password is needed.')
    expect(decodeURIComponent(href)).toContain('On future visits, enter only your email address')
    expect(decodeURIComponent(href)).toContain('https://example.test/?invite=abc#member-portal')
  })
})
