import { describe, expect, it } from 'vitest'
import { getDaysUntilEvent } from './event'

describe('getDaysUntilEvent', () => {
  it('returns a positive countdown before the event', () => {
    expect(getDaysUntilEvent(new Date('2027-07-14T00:00:00+05:30'))).toBe(2)
  })

  it('never returns a negative number', () => {
    expect(getDaysUntilEvent(new Date('2027-08-01T00:00:00+05:30'))).toBe(0)
  })
})
