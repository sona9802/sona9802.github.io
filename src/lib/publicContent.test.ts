import { describe, expect, it } from 'vitest'
import { ANNOUNCEMENTS, COMMITTEES, CONTACT_EMAIL, PROGRAM } from './publicContent'

describe('Phase 1 public content', () => {
  it('covers all three reunion days in date order', () => {
    expect(PROGRAM.map(({ date }) => date)).toEqual(['July 16', 'July 17', 'July 18'])
  })

  it('introduces all seven working committees without duplicates', () => {
    const names = COMMITTEES.map(({ name }) => name)
    expect(names).toHaveLength(7)
    expect(new Set(names).size).toBe(7)
  })

  it('publishes announcements in reverse chronological order', () => {
    const dates = ANNOUNCEMENTS.map(({ date }) => date)
    expect(dates).toEqual([...dates].sort().reverse())
  })

  it('uses the approved public organizer contact', () => {
    expect(CONTACT_EMAIL).toBe('sct9802@gmail.com')
  })
})
