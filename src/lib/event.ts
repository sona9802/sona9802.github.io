export const EVENT = {
  startDate: '2027-07-16T00:00:00+05:30',
  displayDates: 'July 16–18, 2027',
  venue: 'Sona College of Technology · Salem, Tamil Nadu',
} as const

const millisecondsPerDay = 86_400_000

export function getDaysUntilEvent(now: Date): number {
  const difference = new Date(EVENT.startDate).getTime() - now.getTime()
  return Math.max(0, Math.ceil(difference / millisecondsPerDay))
}
