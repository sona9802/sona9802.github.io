import { useCallback, useEffect, useState, type FormEvent } from 'react'
import type { Session } from '@supabase/supabase-js'
import { buildAuthRedirectUrl, CONSENT_LABELS, invitationTokenFromLocation, normalizeCount, type ConsentType } from '../lib/phase2'
import { phase2Enabled, supabase } from '../lib/supabase'

type Profile = {
  id: string
  full_name: string
  preferred_name: string | null
  email_private: string
  city: string | null
  state_region: string | null
  country: string | null
  phone_private: string | null
  whatsapp_private: string | null
  professional_field: string | null
  willing_to_volunteer: boolean
  contact_visibility: 'private' | 'batch'
  verification_status: string
}

type Rsvp = {
  attendance_status: 'undecided' | 'attending' | 'not_attending'
  arrival_date: string | null
  departure_date: string | null
  spouse_count: number
  child_count: number
  dietary_notes_private: string | null
  accessibility_notes_private: string | null
  accommodation_interest: boolean
  transport_interest: boolean
  optional_activity_interest: boolean
}

type Consent = { consent_type: ConsentType; granted: boolean }
type Role = { role_name: string }
type AdminProfile = Pick<Profile, 'id' | 'full_name' | 'email_private' | 'verification_status'> & { department_id: string | null }
type Department = { id: string; code: string; name: string }
type Summary = {
  total_profiles: number
  responses: number
  attending_alumni: number
  attending_spouses: number
  attending_children: number
  undecided: number
  not_attending: number
}

const blankRsvp: Rsvp = {
  attendance_status: 'undecided', arrival_date: null, departure_date: null,
  spouse_count: 0, child_count: 0, dietary_notes_private: null,
  accessibility_notes_private: null, accommodation_interest: false,
  transport_interest: false, optional_activity_interest: false,
}

function Message({ kind, children }: { kind: 'success' | 'error' | 'info'; children: string }) {
  return <p className={`portal-message portal-message--${kind}`} role={kind === 'error' ? 'alert' : 'status'}>{children}</p>
}

export function MemberPortal() {
  const [session, setSession] = useState<Session | null>(null)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [rsvp, setRsvp] = useState<Rsvp>(blankRsvp)
  const [consents, setConsents] = useState<Consent[]>([])
  const [roles, setRoles] = useState<string[]>([])
  const [summary, setSummary] = useState<Summary | null>(null)
  const [adminProfiles, setAdminProfiles] = useState<AdminProfile[]>([])
  const [departments, setDepartments] = useState<Department[]>([])
  const [invitationLink, setInvitationLink] = useState('')
  const [loading, setLoading] = useState(phase2Enabled)
  const [message, setMessage] = useState<{ kind: 'success' | 'error' | 'info'; text: string } | null>(null)

  const loadMember = useCallback(async (userId: string) => {
    if (!supabase) return
    setLoading(true)
    const [profileResult, rsvpResult, consentResult, roleResult] = await Promise.all([
      supabase.from('profiles').select('*').eq('id', userId).maybeSingle(),
      supabase.from('rsvps').select('*').eq('profile_id', userId).maybeSingle(),
      supabase.from('consents').select('consent_type, granted').eq('profile_id', userId),
      supabase.from('user_roles').select('role_name').eq('profile_id', userId),
    ])
    if (profileResult.error) setMessage({ kind: 'error', text: profileResult.error.message })
    setProfile(profileResult.data as Profile | null)
    if (rsvpResult.data) setRsvp(rsvpResult.data as Rsvp)
    setConsents((consentResult.data ?? []) as Consent[])
    const loadedRoles = ((roleResult.data ?? []) as Role[]).map(({ role_name }) => role_name)
    setRoles(loadedRoles)
    if (loadedRoles.some((role) => ['admin', 'technical_admin', 'department_rep'].includes(role))) {
      const summaryResult = await supabase.rpc('get_rsvp_summary')
      if (summaryResult.data?.[0]) setSummary(summaryResult.data[0] as Summary)
    }
    if (loadedRoles.some((role) => ['admin', 'technical_admin'].includes(role))) {
      const [profilesResult, departmentsResult] = await Promise.all([
        supabase.from('profiles').select('id, full_name, email_private, verification_status, department_id').order('full_name'),
        supabase.from('departments').select('id, code, name').eq('active', true).order('name'),
      ])
      setAdminProfiles((profilesResult.data ?? []) as AdminProfile[])
      setDepartments((departmentsResult.data ?? []) as Department[])
    }
    setLoading(false)
  }, [])

  useEffect(() => {
    if (!phase2Enabled || !supabase) return
    const client = supabase
    const callbackParams = new URLSearchParams(window.location.hash.slice(1))
    const callbackError = callbackParams.get('error_description')
    if (callbackError) setMessage({ kind: 'error', text: callbackError.replaceAll('+', ' ') })
    client.auth.getSession().then(({ data }) => {
      setSession(data.session)
      if (data.session) void loadMember(data.session.user.id)
      else setLoading(false)
    })
    const { data: listener } = client.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession)
      if (nextSession) void loadMember(nextSession.user.id)
      else {
        setProfile(null)
        setLoading(false)
      }
    })
    return () => listener.subscription.unsubscribe()
  }, [loadMember])

  useEffect(() => {
    if (session) document.getElementById('member-portal')?.scrollIntoView({ block: 'start' })
  }, [session])

  async function requestMagicLink(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!supabase) return
    const form = new FormData(event.currentTarget)
    const email = String(form.get('email') ?? '').trim()
    const invite = String(form.get('invite') ?? '').trim()
    if (invite) sessionStorage.setItem('reunion-invitation-token', invite)
    const redirectUrl = buildAuthRedirectUrl(window.location.origin, window.location.pathname, invite)
    setLoading(true)
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: redirectUrl, shouldCreateUser: true },
    })
    setLoading(false)
    setMessage(error
      ? { kind: 'error', text: error.message }
      : { kind: 'success', text: 'Check your email for a secure sign-in link. It can take a minute to arrive.' })
  }

  async function acceptInvitation(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!supabase || !session) return
    const form = new FormData(event.currentTarget)
    const token = String(form.get('invite') ?? '').trim()
    const preferredName = String(form.get('preferredName') ?? '').trim()
    setLoading(true)
    const { error } = await supabase.rpc('accept_invitation', { p_token: token, p_preferred_name: preferredName || null })
    if (error) setMessage({ kind: 'error', text: error.message })
    else {
      sessionStorage.removeItem('reunion-invitation-token')
      setMessage({ kind: 'success', text: 'Your invitation is active. Your profile is ready for organizer review.' })
      await loadMember(session.user.id)
    }
    setLoading(false)
  }

  async function saveProfile(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!supabase || !session) return
    const form = new FormData(event.currentTarget)
    const changes = {
      preferred_name: String(form.get('preferred_name') ?? '').trim() || null,
      city: String(form.get('city') ?? '').trim() || null,
      state_region: String(form.get('state_region') ?? '').trim() || null,
      country: String(form.get('country') ?? '').trim() || null,
      phone_private: String(form.get('phone_private') ?? '').trim() || null,
      professional_field: String(form.get('professional_field') ?? '').trim() || null,
      willing_to_volunteer: form.get('willing_to_volunteer') === 'on',
      contact_visibility: (form.get('contact_visibility') === 'batch' ? 'batch' : 'private') as Profile['contact_visibility'],
    }
    const { error } = await supabase.from('profiles').update(changes).eq('id', session.user.id)
    if (error) setMessage({ kind: 'error', text: error.message })
    else {
      setProfile((current) => current ? { ...current, ...changes } : current)
      setMessage({ kind: 'success', text: 'Profile saved.' })
    }
  }

  async function saveRsvp(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!supabase || !session) return
    const form = new FormData(event.currentTarget)
    const changes = {
      profile_id: session.user.id,
      attendance_status: String(form.get('attendance_status')),
      arrival_date: String(form.get('arrival_date') ?? '') || null,
      departure_date: String(form.get('departure_date') ?? '') || null,
      alumni_count: form.get('attendance_status') === 'attending' ? 1 : 0,
      spouse_count: normalizeCount(form.get('spouse_count'), 1),
      child_count: normalizeCount(form.get('child_count'), 10),
      dietary_notes_private: String(form.get('dietary_notes_private') ?? '').trim() || null,
      accessibility_notes_private: String(form.get('accessibility_notes_private') ?? '').trim() || null,
      accommodation_interest: form.get('accommodation_interest') === 'on',
      transport_interest: form.get('transport_interest') === 'on',
      optional_activity_interest: form.get('optional_activity_interest') === 'on',
    }
    const { error } = await supabase.from('rsvps').upsert(changes, { onConflict: 'profile_id' })
    if (error) setMessage({ kind: 'error', text: error.message })
    else {
      setRsvp({ ...rsvp, ...changes, attendance_status: changes.attendance_status as Rsvp['attendance_status'] })
      setMessage({ kind: 'success', text: 'RSVP saved. You may update it at any time.' })
    }
  }

  async function changeConsent(consentType: ConsentType, granted: boolean) {
    if (!supabase || !session) return
    const { error } = await supabase.from('consents').update({ granted, decision_source: granted ? 'profile' : 'withdrawal', recorded_at: new Date().toISOString() })
      .eq('profile_id', session.user.id).eq('consent_type', consentType)
    if (error) setMessage({ kind: 'error', text: error.message })
    else setConsents((items) => items.map((item) => item.consent_type === consentType ? { ...item, granted } : item))
  }

  async function createInvitation(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!supabase) return
    const invitationForm = event.currentTarget
    const form = new FormData(event.currentTarget)
    const { data, error } = await supabase.rpc('create_invitation', {
      p_email: String(form.get('email') ?? '').trim(),
      p_full_name: String(form.get('full_name') ?? '').trim(),
      p_department_id: String(form.get('department_id') ?? '') || null,
      p_expires_days: 14,
    })
    if (error) setMessage({ kind: 'error', text: error.message })
    else if (data?.[0]?.invitation_token) {
      const link = `${window.location.origin}${window.location.pathname}?invite=${data[0].invitation_token}#member-portal`
      setInvitationLink(link)
      setMessage({ kind: 'success', text: 'Invitation created. Copy the secure link now; the token is not stored in readable form.' })
      invitationForm.reset()
    }
  }

  async function reviewProfile(profileId: string, status: 'verified' | 'rejected') {
    if (!supabase) return
    const { error } = await supabase.rpc('review_profile', { p_profile_id: profileId, p_status: status })
    if (error) setMessage({ kind: 'error', text: error.message })
    else {
      setAdminProfiles((items) => items.map((item) => item.id === profileId ? { ...item, verification_status: status } : item))
      setMessage({ kind: 'success', text: `Profile marked ${status}.` })
    }
  }

  if (!phase2Enabled) {
    return (
      <section className="member-portal member-portal--closed" id="member-portal" aria-labelledby="portal-title">
        <p className="section-kicker">Private member area</p>
        <h2 id="portal-title">Invitation access is in pilot preparation.</h2>
        <p>The secure member portal is built, but sign-in remains closed while the organizing team approves the first pilot invitations. No alumni data is being collected here yet.</p>
      </section>
    )
  }

  const storedInvitation = sessionStorage.getItem('reunion-invitation-token') || invitationTokenFromLocation(window.location.search)
  const organizer = roles.some((role) => ['admin', 'technical_admin', 'department_rep'].includes(role))
  const administrator = roles.some((role) => ['admin', 'technical_admin'].includes(role))

  return (
    <section className="member-portal" id="member-portal" aria-labelledby="portal-title">
      <div className="portal-heading">
        <div><p className="section-kicker">Private member area</p><h2 id="portal-title">Your reunion portal.</h2></div>
        {session && <button className="portal-button portal-button--quiet" type="button" onClick={() => void supabase?.auth.signOut()}>Sign out</button>}
      </div>
      {message && <Message kind={message.kind}>{message.text}</Message>}
      {loading && <Message kind="info">Loading your secure reunion record…</Message>}

      {!session && !loading && (
        <form className="portal-card portal-auth" onSubmit={requestMagicLink}>
          <div><span className="portal-step">01</span><h3>Sign in by email</h3><p>Use the email address on your invitation. We will send a one-time secure link—no password needed.</p></div>
          <label>Email address<input name="email" type="email" autoComplete="email" required /></label>
          <label>Invitation token <span>(from your organizer)</span><input name="invite" defaultValue={invitationTokenFromLocation(window.location.search)} autoComplete="off" /></label>
          <button className="portal-button" type="submit">Email my sign-in link</button>
        </form>
      )}

      {session && !profile && !loading && (
        <form className="portal-card portal-auth" onSubmit={acceptInvitation}>
          <div><span className="portal-step">02</span><h3>Activate your invitation</h3><p>Signed in as <strong>{session.user.email}</strong>. Your token is single-use and must match this address.</p></div>
          <label>Invitation token<input name="invite" defaultValue={storedInvitation} required autoComplete="off" /></label>
          <label>Preferred name <span>(optional)</span><input name="preferredName" /></label>
          <button className="portal-button" type="submit">Activate my profile</button>
        </form>
      )}

      {session && profile && (
        <div className="portal-workspace">
          <aside className="portal-sidebar">
            <p className="portal-welcome">Welcome back,<strong>{profile.preferred_name || profile.full_name}</strong></p>
            <span className={`status-pill status-pill--${profile.verification_status}`}>{profile.verification_status}</span>
            <nav aria-label="Member portal navigation"><a href="#my-profile">Profile</a><a href="#my-rsvp">RSVP</a><a href="#my-consent">Privacy choices</a>{organizer && <a href="#organizer-summary">Organizer summary</a>}{administrator && <a href="#admin-console">Admin console</a>}</nav>
          </aside>
          <div className="portal-main">
            <form className="portal-card" id="my-profile" onSubmit={saveProfile}>
              <header><div><span className="portal-step">Profile</span><h3>Your details</h3></div><p>Your email, phone, and location remain private unless you choose batch visibility.</p></header>
              <div className="portal-form-grid">
                <label>Full name<input value={profile.full_name} disabled /></label>
                <label>Email<input value={profile.email_private} disabled /></label>
                <label>Preferred name<input name="preferred_name" defaultValue={profile.preferred_name ?? ''} /></label>
                <label>Professional field<input name="professional_field" defaultValue={profile.professional_field ?? ''} /></label>
                <label>City<input name="city" defaultValue={profile.city ?? ''} /></label>
                <label>State or region<input name="state_region" defaultValue={profile.state_region ?? ''} /></label>
                <label>Country<input name="country" defaultValue={profile.country ?? ''} /></label>
                <label>Phone <span>(organizers only)</span><input name="phone_private" type="tel" defaultValue={profile.phone_private ?? ''} /></label>
              </div>
              <div className="portal-choices"><label><input name="willing_to_volunteer" type="checkbox" defaultChecked={profile.willing_to_volunteer} /> I am willing to volunteer</label><label>Contact visibility<select name="contact_visibility" defaultValue={profile.contact_visibility}><option value="private">Organizers only</option><option value="batch">Verified batch members</option></select></label></div>
              <button className="portal-button" type="submit">Save profile</button>
            </form>

            <form className="portal-card" id="my-rsvp" onSubmit={saveRsvp}>
              <header><div><span className="portal-step">RSVP</span><h3>Will you join us?</h3></div><p>Family and support needs are visible only to authorized organizers.</p></header>
              <fieldset className="portal-radio"><legend>Attendance</legend>{(['attending', 'undecided', 'not_attending'] as const).map((value) => <label key={value}><input type="radio" name="attendance_status" value={value} defaultChecked={rsvp.attendance_status === value} /> {value.replace('_', ' ')}</label>)}</fieldset>
              <div className="portal-form-grid">
                <label>Arrival date<input name="arrival_date" type="date" defaultValue={rsvp.arrival_date ?? ''} /></label>
                <label>Departure date<input name="departure_date" type="date" defaultValue={rsvp.departure_date ?? ''} /></label>
                <label>Spouse / partner<input name="spouse_count" type="number" min="0" max="1" defaultValue={rsvp.spouse_count} /></label>
                <label>Children<input name="child_count" type="number" min="0" max="10" defaultValue={rsvp.child_count} /></label>
                <label className="portal-span">Dietary notes<textarea name="dietary_notes_private" defaultValue={rsvp.dietary_notes_private ?? ''} /></label>
                <label className="portal-span">Accessibility notes<textarea name="accessibility_notes_private" defaultValue={rsvp.accessibility_notes_private ?? ''} /></label>
              </div>
              <div className="portal-checks"><label><input name="accommodation_interest" type="checkbox" defaultChecked={rsvp.accommodation_interest} /> Accommodation information</label><label><input name="transport_interest" type="checkbox" defaultChecked={rsvp.transport_interest} /> Local transport</label><label><input name="optional_activity_interest" type="checkbox" defaultChecked={rsvp.optional_activity_interest} /> Optional family activities</label></div>
              <button className="portal-button" type="submit">Save RSVP</button>
            </form>

            <section className="portal-card" id="my-consent">
              <header><div><span className="portal-step">Privacy</span><h3>Your publication choices</h3></div><p>Every choice starts off. You can withdraw consent at any time.</p></header>
              <div className="consent-list">{consents.map((consent) => <label key={consent.consent_type}><span>{CONSENT_LABELS[consent.consent_type]}</span><input type="checkbox" checked={consent.granted} onChange={(event) => void changeConsent(consent.consent_type, event.target.checked)} /></label>)}</div>
            </section>

            {organizer && summary && <section className="portal-card" id="organizer-summary"><header><div><span className="portal-step">Organizer</span><h3>RSVP snapshot</h3></div><p>{roles.includes('department_rep') && !roles.includes('admin') ? 'Your department only' : 'All active profiles'}</p></header><dl className="summary-grid"><div><dt>Profiles</dt><dd>{summary.total_profiles}</dd></div><div><dt>Responses</dt><dd>{summary.responses}</dd></div><div><dt>Alumni attending</dt><dd>{summary.attending_alumni}</dd></div><div><dt>Family attending</dt><dd>{summary.attending_spouses + summary.attending_children}</dd></div><div><dt>Undecided</dt><dd>{summary.undecided}</dd></div><div><dt>Not attending</dt><dd>{summary.not_attending}</dd></div></dl></section>}

            {administrator && <section className="portal-card" id="admin-console">
              <header><div><span className="portal-step">Administration</span><h3>Invitations & review</h3></div><p>Invitation creation and profile decisions are written to the audit log.</p></header>
              <form className="admin-invite" onSubmit={createInvitation}>
                <label>Alumni name<input name="full_name" required /></label>
                <label>Email address<input name="email" type="email" required /></label>
                <label>Department<select name="department_id" defaultValue=""><option value="">Not assigned</option>{departments.map((department) => <option value={department.id} key={department.id}>{department.code} · {department.name}</option>)}</select></label>
                <button className="portal-button" type="submit">Create invitation</button>
              </form>
              {invitationLink && <div className="invitation-result"><p>Secure invitation link</p><code>{invitationLink}</code><button className="portal-button portal-button--copy" type="button" onClick={() => void navigator.clipboard.writeText(invitationLink)}>Copy link</button></div>}
              <div className="review-list">
                <div className="review-list__head"><span>Member</span><span>Status</span><span>Review</span></div>
                {adminProfiles.map((item) => <div className="review-row" key={item.id}><span><strong>{item.full_name}</strong><small>{item.email_private}</small></span><span className={`status-pill status-pill--${item.verification_status}`}>{item.verification_status}</span><span>{item.verification_status === 'pending' ? <><button type="button" onClick={() => void reviewProfile(item.id, 'verified')}>Verify</button><button type="button" onClick={() => void reviewProfile(item.id, 'rejected')}>Reject</button></> : '—'}</span></div>)}
              </div>
            </section>}
          </div>
        </div>
      )}
    </section>
  )
}
