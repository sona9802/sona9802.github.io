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

export function buildAuthRedirectUrl(origin: string, pathname: string, invitationToken: string): string {
  const redirectUrl = new URL(pathname, origin)
  if (invitationToken) redirectUrl.searchParams.set('invite', invitationToken)
  return redirectUrl.toString()
}

export function buildInvitationEmailHref(email: string, fullName: string, invitationLink: string): string {
  const subject = 'Your SCT 1998–2002 Reunion Portal invitation'
  const body = [
    `Hello ${fullName},`,
    '',
    'You have been invited to the SCT 1998–2002 Silver Jubilee Reunion Portal.',
    '',
    'Open this complete secure invitation link:',
    invitationLink,
    '',
    'Invitation code: You do not need to copy a separate code. It is already embedded in the secure link above.',
    '',
    'Next steps:',
    '1. Open the secure invitation link.',
    '2. Enter this same email address and request the one-time secure sign-in link. No username or password is needed.',
    '3. Open the sign-in email. You will return to the portal with your invitation code preserved.',
    '4. Select “Activate once and enter portal” and complete your reunion details.',
    '5. On future visits, enter only your email address; you will not need the invitation code again.',
    '',
    'If either link expires, contact the organizing team for a new invitation.',
    '',
    'SCT 1998–2002 Reunion Organizing Team',
  ].join('\n')
  return `mailto:${encodeURIComponent(email)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`
}
