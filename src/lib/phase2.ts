export const CONSENT_LABELS = {
  directory_visibility: 'Include me in the private batch directory',
  biography_publication: 'Publish my biography in reunion materials',
  profile_photo_publication: 'Publish my profile photograph',
  reunion_photo_publication: 'Use reunion photographs that include me',
  book_publication: 'Include my approved material in the reunion book',
} as const

export type ConsentType = keyof typeof CONSENT_LABELS

export function normalizeCount(value: FormDataEntryValue | null, maximum: number): number {
  const parsed = Number(value)
  return Number.isFinite(parsed) ? Math.min(maximum, Math.max(0, Math.trunc(parsed))) : 0
}

export function invitationTokenFromLocation(search: string): string {
  return new URLSearchParams(search).get('invite')?.trim() ?? ''
}
