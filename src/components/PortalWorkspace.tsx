import { useCallback, useEffect, useMemo, useState, type FormEvent, type KeyboardEvent } from 'react'
import { supabase } from '../lib/supabase'
import { AdminOperations } from './AdminOperations'

type Department = { id: string; code: string; name: string }
type Person = { id: string; full_name: string; preferred_name?: string | null; email_private?: string; verification_status?: string; department_id?: string | null }
type Committee = { id: string; name: string; purpose: string; responsibilities: string | null; deliverables: string | null; status: string; meeting_frequency: string | null; requires_india_coordinator: boolean }
type CommitteeMember = { committee_id: string; profile_id: string; committee_role: string; active: boolean }
type Task = { id: string; task_number: number; committee_id: string; owner_profile_id: string | null; title: string; description: string; priority: string; status: string; due_date: string | null; progress_note: string | null }
type CommitteeRosterMember = CommitteeMember & { display_name: string; department_code: string | null }
type CommitteeWorkspaceTask = Task & { owner_display_name: string | null }
type Announcement = { id: string; title: string; body: string; audience_type: string; pinned: boolean; publish_at: string | null; created_at: string }
type Biography = { id: string; profile_id: string; original_text: string; submitted_text: string | null; edited_text: string | null; editor_note: string | null; editorial_status: string; version: number }
type MediaAsset = { id: string; uploader_profile_id: string; storage_bucket: string; storage_path: string; media_type: string; category: string; caption: string | null; moderation_status: string; book_approved: boolean; public_gallery_approved: boolean }
type Notice = { id: string; title: string; body: string; read_at: string | null; created_at: string }
type DirectoryEntry = { profile_id: string; display_name: string; department_code: string | null; city: string | null; state_region: string | null; country: string | null; professional_field: string | null; directory_summary: string | null }
type ProgramItem = { id: string; title: string; starts_at: string; ends_at: string; venue: string | null; status: string; is_public: boolean }
type Shift = { id: string; title: string; starts_at: string; ends_at: string; location: string | null; required_volunteers: number; status: string }
type Faculty = { id: string; full_name: string; affiliation: string | null; invite_status: string; attendance_status: string }
type Coverage = { department_id: string; code: string; name: string; representative_count: number; has_india_coordinator: boolean; needs_attention: boolean }

type Props = {
  userId: string
  roles: string[]
  departments: Department[]
  profiles: Person[]
  activeSection: string
}

const ADMIN_ROLES = ['admin', 'technical_admin']
const ROLE_OPTIONS = ['member', 'department_rep', 'committee_lead', 'invitation_manager', 'editor', 'event_operator', 'finance', 'auditor', 'admin']
const TASK_STATUSES = ['ready', 'in_progress', 'blocked', 'completed']
const COMMITTEE_ROLE_LABELS: Record<string, string> = {
  lead: 'Committee lead', deputy: 'Deputy lead', india_coordinator: 'India coordinator',
  finance_liaison: 'Finance liaison', member: 'Member',
}

function displayPerson(person: Person | undefined, fallback = 'Unassigned') {
  return person ? person.preferred_name || person.full_name : fallback
}

function downloadJson(name: string, payload: unknown) {
  const url = URL.createObjectURL(new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' }))
  const link = document.createElement('a')
  link.href = url
  link.download = name
  link.click()
  URL.revokeObjectURL(url)
}

export function PortalWorkspace({ userId, roles, departments, profiles, activeSection }: Props) {
  const administrator = roles.some((role) => ADMIN_ROLES.includes(role))
  const editor = administrator || roles.includes('editor')
  const organizer = administrator || roles.includes('department_rep') || roles.includes('committee_lead')
  const eventOperator = administrator || roles.includes('event_operator')
  const [committees, setCommittees] = useState<Committee[]>([])
  const [tasks, setTasks] = useState<Task[]>([])
  const [committeeRoster, setCommitteeRoster] = useState<CommitteeRosterMember[]>([])
  const [committeeTasks, setCommitteeTasks] = useState<CommitteeWorkspaceTask[]>([])
  const [activeCommitteeId, setActiveCommitteeId] = useState<string | null>(null)
  const [announcements, setAnnouncements] = useState<Announcement[]>([])
  const [biographies, setBiographies] = useState<Biography[]>([])
  const [media, setMedia] = useState<MediaAsset[]>([])
  const [notifications, setNotifications] = useState<Notice[]>([])
  const [directory, setDirectory] = useState<DirectoryEntry[]>([])
  const [directoryQuery, setDirectoryQuery] = useState('')
  const [dashboard, setDashboard] = useState<Record<string, number> | null>(null)
  const [eventDashboard, setEventDashboard] = useState<Record<string, number> | null>(null)
  const [coverage, setCoverage] = useState<Coverage[]>([])
  const [program, setProgram] = useState<ProgramItem[]>([])
  const [shifts, setShifts] = useState<Shift[]>([])
  const [faculty, setFaculty] = useState<Faculty[]>([])
  const [editorLabels, setEditorLabels] = useState<Person[]>([])
  const [message, setMessage] = useState<{ kind: 'success' | 'error' | 'info'; text: string } | null>(null)
  const [busy, setBusy] = useState(false)

  const allPeople = useMemo(() => {
    const byId = new Map<string, Person>()
    for (const person of [...profiles, ...editorLabels]) byId.set(person.id, person)
    return [...byId.values()]
  }, [profiles, editorLabels])

  const loadWorkspace = useCallback(async () => {
    if (!supabase) return
    const requests = await Promise.all([
      supabase.from('committees').select('id,name,purpose,responsibilities,deliverables,status,meeting_frequency,requires_india_coordinator').order('name'),
      supabase.from('tasks').select('id,task_number,committee_id,owner_profile_id,title,description,priority,status,due_date,progress_note').order('due_date', { ascending: true, nullsFirst: false }),
      supabase.from('announcements').select('id,title,body,audience_type,pinned,publish_at,created_at').order('pinned', { ascending: false }).order('created_at', { ascending: false }),
      supabase.from('biographies').select('id,profile_id,original_text,submitted_text,edited_text,editor_note,editorial_status,version').order('updated_at', { ascending: false }),
      supabase.from('media_assets').select('id,uploader_profile_id,storage_bucket,storage_path,media_type,category,caption,moderation_status,book_approved,public_gallery_approved').order('created_at', { ascending: false }),
      supabase.from('notifications').select('id,title,body,read_at,created_at').order('created_at', { ascending: false }).limit(20),
      supabase.rpc('member_directory', { p_query: directoryQuery }),
      supabase.from('program_items').select('id,title,starts_at,ends_at,venue,status,is_public').order('starts_at'),
      supabase.from('volunteer_shifts').select('id,title,starts_at,ends_at,location,required_volunteers,status').order('starts_at'),
      supabase.rpc('committee_workspace_members'),
      supabase.rpc('committee_workspace_tasks'),
    ])
    const loadedCommittees = (requests[0].data ?? []) as Committee[]
    setCommittees(loadedCommittees)
    setActiveCommitteeId((current) => current && loadedCommittees.some((item) => item.id === current) ? current : loadedCommittees[0]?.id ?? null)
    setTasks((requests[1].data ?? []) as Task[])
    setAnnouncements((requests[2].data ?? []) as Announcement[])
    setBiographies((requests[3].data ?? []) as Biography[])
    setMedia((requests[4].data ?? []) as MediaAsset[])
    setNotifications((requests[5].data ?? []) as Notice[])
    setDirectory((requests[6].data ?? []) as DirectoryEntry[])
    setProgram((requests[7].data ?? []) as ProgramItem[])
    setShifts((requests[8].data ?? []) as Shift[])
    setCommitteeRoster((requests[9].data ?? []) as CommitteeRosterMember[])
    setCommitteeTasks((requests[10].data ?? []) as CommitteeWorkspaceTask[])

    if (organizer) {
      const [dashboardResult, coverageResult] = await Promise.all([
        supabase.rpc('organizer_dashboard'),
        supabase.rpc('department_coverage'),
      ])
      setDashboard((dashboardResult.data ?? null) as Record<string, number> | null)
      setCoverage((coverageResult.data ?? []) as Coverage[])
    }
    if (editor || eventOperator) {
      const labels = await supabase.rpc(editor ? 'editor_profile_labels' : 'event_operator_profile_labels')
      setEditorLabels(((labels.data ?? []) as Array<{ profile_id: string; display_name: string }>).map((item) => ({ id: item.profile_id, full_name: item.display_name })))
    }
    if (eventOperator) {
      const [eventResult, facultyResult] = await Promise.all([
        supabase.rpc('event_operations_dashboard'),
        supabase.from('faculty_staff').select('id,full_name,affiliation,invite_status,attendance_status').order('full_name'),
      ])
      setEventDashboard((eventResult.data ?? null) as Record<string, number> | null)
      setFaculty((facultyResult.data ?? []) as Faculty[])
    }
    const firstError = requests.find((request) => request.error)?.error
    if (firstError) setMessage({ kind: 'error', text: firstError.message })
  }, [directoryQuery, editor, eventOperator, organizer])

  useEffect(() => { void loadWorkspace() }, [loadWorkspace])

  async function run(action: () => PromiseLike<{ error: { message: string } | null }>, success: string) {
    setBusy(true)
    const { error } = await action()
    setBusy(false)
    setMessage(error ? { kind: 'error', text: error.message } : { kind: 'success', text: success })
    if (!error) await loadWorkspace()
  }

  async function createTask(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    await run(() => supabase!.rpc('create_task', {
      p_committee_id: String(form.get('committee_id')),
      p_title: String(form.get('title')),
      p_description: String(form.get('description') ?? ''),
      p_owner_profile_id: String(form.get('owner_profile_id') ?? '') || null,
      p_priority: String(form.get('priority')),
      p_status: 'ready',
      p_due_date: String(form.get('due_date') ?? '') || null,
    }), 'Task created and audited.')
    event.currentTarget.reset()
  }

  async function updateTask(taskId: string, status: string) {
    await run(() => supabase!.rpc('update_task_progress', { p_task_id: taskId, p_status: status, p_progress_note: null }), 'Task progress updated.')
  }

  async function addTaskComment(event: FormEvent<HTMLFormElement>, taskId: string) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    await run(() => supabase!.from('task_comments').insert({ task_id: taskId, author_profile_id: userId, body: String(form.get('body')) }), 'Comment added.')
    event.currentTarget.reset()
  }

  async function publishAnnouncement(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    await run(() => supabase!.from('announcements').insert({
      title: String(form.get('title')), body: String(form.get('body')),
      audience_type: String(form.get('audience_type')), status: 'published',
      pinned: form.get('pinned') === 'on', publish_at: new Date().toISOString(),
      published_at: new Date().toISOString(), author_id: userId,
    }), 'Announcement published.')
    event.currentTarget.reset()
  }

  async function saveBiography(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const text = String(new FormData(event.currentTarget).get('biography') ?? '')
    await run(() => supabase!.rpc('save_biography_draft', { p_text: text }), 'Biography draft saved.')
  }

  async function biographyAction(action: 'submit' | 'approve' | 'withdraw') {
    const call = action === 'submit' ? supabase!.rpc('submit_biography')
      : action === 'approve' ? supabase!.rpc('approve_edited_biography')
        : supabase!.rpc('withdraw_biography')
    await run(() => call, `Biography ${action === 'submit' ? 'submitted' : action === 'approve' ? 'approved' : 'withdrawn'}.`)
  }

  async function reviewBiography(event: FormEvent<HTMLFormElement>, biographyId: string) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    await run(() => supabase!.rpc('review_biography', {
      p_biography_id: biographyId,
      p_status: String(form.get('status')),
      p_edited_text: String(form.get('edited_text') ?? '') || null,
      p_editor_note: String(form.get('editor_note') ?? '') || null,
    }), 'Biography review recorded.')
  }

  async function uploadMedia(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const formElement = event.currentTarget
    const form = new FormData(formElement)
    const file = form.get('file') as File
    const mediaType = String(form.get('media_type'))
    const limit = mediaType === 'profile_photo' ? 1024 * 1024 : 2 * 1024 * 1024
    if (!file || !['image/jpeg', 'image/png', 'image/webp'].includes(file.type) || file.size > limit) {
      setMessage({ kind: 'error', text: `Choose a JPEG, PNG, or WebP image under ${mediaType === 'profile_photo' ? '1 MB' : '2 MB'}.` })
      return
    }
    setBusy(true)
    const assetId = crypto.randomUUID()
    const extension = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg'
    const bucket = mediaType === 'profile_photo' ? 'profile-photos-private' : 'reunion-photos-private'
    const path = `${userId}/${assetId}/${assetId}.${extension}`
    const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', await file.arrayBuffer()))].map((byte) => byte.toString(16).padStart(2, '0')).join('')
    const upload = await supabase!.storage.from(bucket).upload(path, file, { contentType: file.type, upsert: false })
    if (upload.error) {
      setBusy(false)
      setMessage({ kind: 'error', text: upload.error.message })
      return
    }
    const registration = await supabase!.rpc('register_media_asset', {
      p_asset_id: assetId, p_bucket: bucket, p_path: path, p_media_type: mediaType,
      p_category: String(form.get('category')), p_caption: String(form.get('caption') ?? ''),
      p_mime_type: file.type, p_file_size_bytes: file.size, p_checksum: hash,
    })
    setBusy(false)
    setMessage(registration.error ? { kind: 'error', text: registration.error.message } : { kind: 'success', text: 'Private image uploaded. Submit it when ready for review.' })
    if (!registration.error) { formElement.reset(); await loadWorkspace() }
  }

  async function viewMedia(asset: MediaAsset) {
    const { data, error } = await supabase!.storage.from(asset.storage_bucket).createSignedUrl(asset.storage_path, 300)
    if (error) setMessage({ kind: 'error', text: error.message })
    else window.open(data.signedUrl, '_blank', 'noopener,noreferrer')
  }

  async function reviewMedia(event: FormEvent<HTMLFormElement>, assetId: string) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    await run(() => supabase!.rpc('review_media_asset', {
      p_asset_id: assetId, p_status: String(form.get('status')),
      p_reviewer_note: String(form.get('reviewer_note') ?? '') || null,
      p_book_approved: form.get('book_approved') === 'on',
      p_public_gallery_approved: form.get('public_gallery_approved') === 'on',
    }), 'Media review recorded.')
  }

  async function assignRole(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    await run(() => supabase!.rpc('set_user_role', {
      p_profile_id: String(form.get('profile_id')), p_role: String(form.get('role')),
      p_enabled: String(form.get('mode')) === 'grant',
    }), 'Role assignment updated and audited.')
  }

  async function assignCommittee(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    await run(() => supabase!.rpc('set_committee_member', {
      p_committee_id: String(form.get('committee_id')), p_profile_id: String(form.get('profile_id')),
      p_committee_role: String(form.get('committee_role')), p_active: true,
    }), 'Committee membership updated.')
  }

  async function assignDepartmentRepresentative(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    await run(() => supabase!.rpc('assign_department_representative', {
      p_profile_id: String(form.get('profile_id')), p_department_id: String(form.get('department_id')),
      p_is_india_coordinator: form.get('india') === 'on',
    }), 'Department representative assigned.')
  }

  async function createDepartment(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    await run(() => supabase!.from('departments').insert({ code: String(form.get('code')).trim().toUpperCase(), name: String(form.get('name')).trim() }), 'Department created.')
    event.currentTarget.reset()
  }

  async function createProgramItem(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    await run(() => supabase!.from('program_items').insert({
      title: String(form.get('title')), starts_at: String(form.get('starts_at')),
      ends_at: String(form.get('ends_at')), venue: String(form.get('venue') ?? '') || null,
      status: 'confirmed', is_public: form.get('is_public') === 'on', created_by: userId,
    }), 'Program item created.')
    event.currentTarget.reset()
  }

  async function createShift(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    await run(() => supabase!.from('volunteer_shifts').insert({
      title: String(form.get('title')), starts_at: String(form.get('starts_at')),
      ends_at: String(form.get('ends_at')), location: String(form.get('location') ?? '') || null,
      required_volunteers: Number(form.get('required_volunteers')), created_by: userId,
    }), 'Volunteer shift created.')
    event.currentTarget.reset()
  }

  async function addFaculty(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    await run(() => supabase!.from('faculty_staff').insert({
      full_name: String(form.get('full_name')), affiliation: String(form.get('affiliation') ?? '') || null,
      invite_status: 'not_started', attendance_status: 'undecided', created_by: userId,
    }), 'Faculty or staff record created.')
    event.currentTarget.reset()
  }

  async function checkIn(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    const target = String(form.get('target'))
    const [kind, id] = target.split(':')
    await run(() => supabase!.rpc('check_in_attendee', {
      p_profile_id: kind === 'profile' ? id : null, p_faculty_staff_id: kind === 'faculty' ? id : null,
      p_party_adults: Number(form.get('party_adults')), p_party_children: Number(form.get('party_children')), p_notes: null,
    }), 'Attendee checked in.')
  }

  async function submitFeedback(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    await run(() => supabase!.from('feedback_submissions').insert({ profile_id: userId, category: String(form.get('category')), message: String(form.get('message')) }), 'Thank you—your feedback is recorded.')
    event.currentTarget.reset()
  }

  async function submitDataRequest(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    await run(() => supabase!.from('data_requests').insert({ profile_id: userId, request_type: String(form.get('request_type')), details: String(form.get('details') ?? '') || null }), 'Your privacy request is recorded.')
    event.currentTarget.reset()
  }

  async function generateBookExport() {
    setBusy(true)
    const { data, error } = await supabase!.rpc('generate_book_export')
    setBusy(false)
    if (error) setMessage({ kind: 'error', text: error.message })
    else {
      const result = data?.[0]
      if (!result) {
        setMessage({ kind: 'error', text: 'The export completed without returning a manifest. Please try again.' })
        return
      }
      downloadJson(`reunion-book-export-${new Date().toISOString().slice(0, 10)}.json`, result.export_payload ?? {})
      setMessage({ kind: 'success', text: `Consent-filtered export generated; access record expires ${new Date(result.expires_at).toLocaleString()}.` })
    }
  }

  const myBiography = biographies.find((item) => item.profile_id === userId)
  const myMedia = media.filter((item) => item.uploader_profile_id === userId)
  const relevantTasks = tasks
  const activeCommittee = committees.find((item) => item.id === activeCommitteeId) ?? committees[0]
  const activeCommitteeMembers = committeeRoster.filter((item) => item.committee_id === activeCommittee?.id)
  const activeCommitteeTasks = committeeTasks.filter((item) => item.committee_id === activeCommittee?.id)
  const keyCommitteePeople = activeCommitteeMembers.filter((item) => item.active && item.committee_role !== 'member')
  const activeTaskCount = activeCommitteeTasks.filter((item) => !['completed', 'cancelled'].includes(item.status)).length
  const panelProps = (id: string) => ({
    role: 'tabpanel' as const,
    'aria-labelledby': `portal-tab-${id}`,
    hidden: activeSection !== id,
  })

  function selectAdjacentCommittee(event: KeyboardEvent<HTMLButtonElement>, index: number) {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return
    event.preventDefault()
    const nextIndex = event.key === 'Home' ? 0
      : event.key === 'End' ? committees.length - 1
        : (index + (event.key === 'ArrowRight' ? 1 : -1) + committees.length) % committees.length
    const nextCommittee = committees[nextIndex]
    if (!nextCommittee) return
    setActiveCommitteeId(nextCommittee.id)
    document.getElementById(`committee-tab-${nextCommittee.id}`)?.focus()
  }

  return (
    <>
      {message && <p className={`portal-message portal-message--${message.kind}`} role={message.kind === 'error' ? 'alert' : 'status'}>{message.text}</p>}
      {busy && <p className="portal-message portal-message--info" role="status">Saving securely…</p>}

      {notifications.length > 0 && <section className="portal-card portal-card--companion" id="notifications" aria-label="Notifications" hidden={activeSection !== 'member-announcements'}>
        <header><div><span className="portal-step">Inbox</span><h3>Notifications</h3></div><p>Assignments and review requests that need your attention.</p></header>
        <div className="workspace-list">{notifications.map((notice) => <article key={notice.id} className={notice.read_at ? '' : 'is-unread'}><div><strong>{notice.title}</strong><p>{notice.body}</p></div>{!notice.read_at && <button type="button" onClick={() => void run(() => supabase!.rpc('mark_notification_read', { p_notification_id: notice.id }), 'Notification marked read.')}>Mark read</button>}</article>)}</div>
      </section>}

      <section className="portal-card" id="member-directory" {...panelProps('member-directory')}>
        <header><div><span className="portal-step">Directory</span><h3>Batch directory</h3></div><p>Only members who opted into directory visibility appear here.</p></header>
        <form className="inline-form" onSubmit={(event) => { event.preventDefault(); void loadWorkspace() }}><label>Search by name or branch<input value={directoryQuery} onChange={(event) => setDirectoryQuery(event.target.value)} /></label><button className="portal-button" type="submit">Search</button></form>
        <div className="card-grid">{directory.map((entry) => <article key={entry.profile_id} className="mini-card"><strong>{entry.display_name}{entry.department_code ? ` – ${entry.department_code}` : ''}</strong><p>{[entry.city, entry.state_region, entry.country].filter(Boolean).join(', ') || 'Location not shared'}</p><small>{entry.professional_field || entry.directory_summary || 'No public summary yet'}</small></article>)}</div>
      </section>

      <section className="portal-card" id="committee-workspace" {...panelProps('committee-workspace')}>
        <header><div><span className="portal-step">Committees</span><h3>Working teams</h3></div><p>Select a team to see its responsibilities, current tasks, active leaders, and complete roster.</p></header>
        {committees.length === 0 ? <p className="committee-empty">No committees are available yet.</p> : <>
          <div className="committee-tabs" role="tablist" aria-label="Reunion working teams">
            {committees.map((committee, index) => {
              const selected = committee.id === activeCommittee?.id
              const memberCount = committeeRoster.filter((item) => item.committee_id === committee.id && item.active).length
              const taskCount = committeeTasks.filter((item) => item.committee_id === committee.id && !['completed', 'cancelled'].includes(item.status)).length
              return <button
                id={`committee-tab-${committee.id}`}
                className={selected ? 'committee-tab is-active' : 'committee-tab'}
                key={committee.id}
                type="button"
                role="tab"
                aria-selected={selected}
                aria-controls={`committee-panel-${committee.id}`}
                tabIndex={selected ? 0 : -1}
                onClick={() => setActiveCommitteeId(committee.id)}
                onKeyDown={(event) => selectAdjacentCommittee(event, index)}
              ><span>{committee.name}</span><small>{taskCount} open · {memberCount} members</small></button>
            })}
          </div>
          {activeCommittee && <div className="committee-panel" id={`committee-panel-${activeCommittee.id}`} role="tabpanel" aria-labelledby={`committee-tab-${activeCommittee.id}`}>
            <div className="committee-panel__intro">
              <div><span className={`status-pill status-pill--${activeCommittee.status}`}>{activeCommittee.status}</span><h4>{activeCommittee.name}</h4><p>{activeCommittee.purpose}</p></div>
              <dl className="committee-stats"><div><dt>Open tasks</dt><dd>{activeTaskCount}</dd></div><div><dt>Active members</dt><dd>{activeCommitteeMembers.filter((item) => item.active).length}</dd></div><div><dt>Meeting cadence</dt><dd>{activeCommittee.meeting_frequency || 'To be set'}</dd></div></dl>
            </div>
            <div className="committee-brief">
              <div><h5>What this team handles</h5><ul>{(activeCommittee.responsibilities || activeCommittee.purpose).split(',').map((item) => <li key={item.trim()}>{item.trim()}</li>)}</ul></div>
              <div><h5>Expected result</h5><p>{activeCommittee.deliverables || 'Deliverables are being finalized.'}</p></div>
            </div>
            <section className="committee-panel__section" aria-labelledby={`committee-tasks-${activeCommittee.id}`}>
              <div className="committee-section-heading"><div><span>Work</span><h5 id={`committee-tasks-${activeCommittee.id}`}>Tasks</h5></div><strong>{activeCommitteeTasks.length} total</strong></div>
              {activeCommitteeTasks.length === 0 ? <p className="committee-empty">No tasks have been added for this team yet.</p> : <div className="committee-task-list">{activeCommitteeTasks.map((task) => <article key={task.id}>
                <div><span className={`task-status task-status--${task.status}`}>{task.status.replaceAll('_', ' ')}</span><h6>{task.title}</h6><p>{task.description || 'No description has been added.'}</p></div>
                <dl><div><dt>Owner</dt><dd>{task.owner_display_name || 'Unassigned'}</dd></div><div><dt>Due</dt><dd>{task.due_date ? new Date(`${task.due_date}T00:00:00`).toLocaleDateString() : 'Not set'}</dd></div><div><dt>Priority</dt><dd>{task.priority}</dd></div></dl>
              </article>)}</div>}
            </section>
            <div className="committee-people-grid">
              <section className="committee-panel__section" aria-labelledby={`committee-key-${activeCommittee.id}`}>
                <div className="committee-section-heading"><div><span>Leadership</span><h5 id={`committee-key-${activeCommittee.id}`}>Key people</h5></div><strong>{keyCommitteePeople.length}</strong></div>
                {keyCommitteePeople.length === 0 ? <p className="committee-empty">No leads or coordinators have been assigned yet.</p> : <ul className="committee-roster committee-roster--key">{keyCommitteePeople.map((member) => <li key={member.profile_id}><span className="member-avatar" aria-hidden="true">{member.display_name.charAt(0).toUpperCase()}</span><span><strong>{member.display_name}</strong><small>{COMMITTEE_ROLE_LABELS[member.committee_role] || member.committee_role.replaceAll('_', ' ')}{member.department_code ? ` · ${member.department_code}` : ''}</small></span></li>)}</ul>}
              </section>
              <section className="committee-panel__section" aria-labelledby={`committee-roster-${activeCommittee.id}`}>
                <div className="committee-section-heading"><div><span>Roster</span><h5 id={`committee-roster-${activeCommittee.id}`}>All registered members</h5></div><strong>{activeCommitteeMembers.length}</strong></div>
                {activeCommitteeMembers.length === 0 ? <p className="committee-empty">No members are registered with this team yet.</p> : <ul className="committee-roster">{activeCommitteeMembers.map((member) => <li key={member.profile_id} className={member.active ? '' : 'is-inactive'}><span className="member-avatar" aria-hidden="true">{member.display_name.charAt(0).toUpperCase()}</span><span><strong>{member.display_name}</strong><small>{COMMITTEE_ROLE_LABELS[member.committee_role] || member.committee_role.replaceAll('_', ' ')}{member.department_code ? ` · ${member.department_code}` : ''}{member.active ? '' : ' · Inactive'}</small></span></li>)}</ul>}
              </section>
            </div>
          </div>}
        </>}
      </section>

      <section className="portal-card" id="task-board" {...panelProps('task-board')}>
        <header><div><span className="portal-step">Tasks</span><h3>My work and committee board</h3></div><p>Overdue and blocked work stays visible until resolved.</p></header>
        {(administrator || roles.includes('committee_lead')) && <form className="workspace-form" onSubmit={createTask}><label>Committee<select name="committee_id" required><option value="">Choose</option>{committees.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label>Task title<input name="title" required /></label><label>Owner<select name="owner_profile_id"><option value="">Unassigned</option>{allPeople.map((person) => <option key={person.id} value={person.id}>{displayPerson(person)}</option>)}</select></label><label>Priority<select name="priority" defaultValue="medium"><option>low</option><option>medium</option><option>high</option><option>critical</option></select></label><label>Due date<input name="due_date" type="date" /></label><label className="portal-span">Description<textarea name="description" /></label><button className="portal-button" type="submit">Create task</button></form>}
        <div className="task-grid">{relevantTasks.map((task) => <article className={`task-card task-card--${task.priority}`} key={task.id}><div><small>#{task.task_number} · {committees.find((item) => item.id === task.committee_id)?.name}</small><h4>{task.title}</h4><p>{task.description}</p></div><dl><div><dt>Owner</dt><dd>{displayPerson(allPeople.find((item) => item.id === task.owner_profile_id))}</dd></div><div><dt>Due</dt><dd>{task.due_date || 'Not set'}</dd></div></dl><label>Status<select value={task.status} onChange={(event) => void updateTask(task.id, event.target.value)}>{TASK_STATUSES.map((status) => <option key={status}>{status}</option>)}</select></label><form className="inline-form" onSubmit={(event) => void addTaskComment(event, task.id)}><label>Progress comment<input name="body" required /></label><button type="submit">Add</button></form></article>)}</div>
      </section>

      <section className="portal-card" id="member-announcements" {...panelProps('member-announcements')}>
        <header><div><span className="portal-step">Updates</span><h3>Member announcements</h3></div><p>Public, batch, organizer, department, and committee updates.</p></header>
        {administrator && <form className="workspace-form" onSubmit={publishAnnouncement}><label>Title<input name="title" required /></label><label>Audience<select name="audience_type" defaultValue="all_members"><option value="public">Public</option><option value="all_members">All members</option><option value="organizers">Organizers</option></select></label><label className="portal-span">Message<textarea name="body" required /></label><label><input type="checkbox" name="pinned" /> Pin this update</label><button className="portal-button" type="submit">Publish</button></form>}
        <div className="workspace-list">{announcements.map((item) => <article key={item.id}><div><strong>{item.pinned ? 'Pinned · ' : ''}{item.title}</strong><p>{item.body}</p><small>{item.audience_type.replaceAll('_', ' ')} · {new Date(item.publish_at || item.created_at).toLocaleDateString()}</small></div></article>)}</div>
      </section>

      <section className="portal-card" id="biography-editor" {...panelProps('biography-editor')}>
        <header><div><span className="portal-step">Story</span><h3>Your biography</h3></div><p>Suggested length: 150–300 words. Publication always requires separate consent.</p></header>
        <form onSubmit={saveBiography}><label>Biography draft<textarea name="biography" rows={9} defaultValue={myBiography?.original_text ?? ''} disabled={['edited', 'member_approved', 'publication_approved'].includes(myBiography?.editorial_status ?? '')} /></label><div className="button-row"><button className="portal-button" type="submit">Save draft</button><button type="button" onClick={() => void biographyAction('submit')}>Submit for review</button>{myBiography?.editorial_status === 'edited' && <button type="button" onClick={() => void biographyAction('approve')}>Approve edited version</button>}{myBiography && <button type="button" className="danger-button" onClick={() => void biographyAction('withdraw')}>Withdraw</button>}</div></form>
        {myBiography && <p className="subtle-status">Status: <strong>{myBiography.editorial_status.replaceAll('_', ' ')}</strong> · Version {myBiography.version}{myBiography.editor_note ? ` · ${myBiography.editor_note}` : ''}</p>}
      </section>

      <section className="portal-card" id="media-library" {...panelProps('media-library')}>
        <header><div><span className="portal-step">Photos</span><h3>Private media library</h3></div><p>Profile photos: 1 MB. Memory photos: 2 MB. JPEG, PNG, or WebP only.</p></header>
        <form className="workspace-form" onSubmit={uploadMedia}><label>Type<select name="media_type" defaultValue="profile_photo"><option value="profile_photo">Profile photo</option><option value="memory_photo">Memory photo</option></select></label><label>Category<select name="category" defaultValue="current"><option value="current">Current</option><option value="college_era">College era</option><option value="reunion">Reunion</option><option value="family">Family</option><option value="other">Other</option></select></label><label>Image<input name="file" type="file" accept="image/jpeg,image/png,image/webp" required /></label><label className="portal-span">Caption<input name="caption" /></label><button className="portal-button" type="submit">Upload privately</button></form>
        <div className="workspace-list">{myMedia.map((asset) => <article key={asset.id}><div><strong>{asset.media_type.replaceAll('_', ' ')}</strong><p>{asset.caption || 'No caption'} · {asset.moderation_status}</p></div><div className="button-row"><button type="button" onClick={() => void viewMedia(asset)}>Preview</button>{['private', 'revision_requested', 'rejected'].includes(asset.moderation_status) && <button type="button" onClick={() => void run(() => supabase!.rpc('submit_media_asset', { p_asset_id: asset.id }), 'Photo submitted for review.')}>Submit</button>}<button className="danger-button" type="button" onClick={() => void run(() => supabase!.rpc('delete_media_asset', { p_asset_id: asset.id }), 'Photo deleted from storage and the portal.')}>Delete</button></div></article>)}</div>
      </section>

      {organizer && dashboard && <section className="portal-card" id="organizer-dashboard" {...panelProps('organizer-dashboard')}><header><div><span className="portal-step">Dashboard</span><h3>Organizer control room</h3></div><p>Live directory, committee, and task health.</p></header><dl className="summary-grid">{Object.entries(dashboard).map(([label, value]) => <div key={label}><dt>{label.replaceAll('_', ' ')}</dt><dd>{value}</dd></div>)}</dl><div className="coverage-grid">{coverage.map((item) => <article className={item.needs_attention ? 'needs-attention' : ''} key={item.department_id}><strong>{item.code}</strong><span>{item.representative_count} reps</span><span>{item.has_india_coordinator ? 'India coordinator ✓' : 'India coordinator needed'}</span></article>)}</div></section>}

      {editor && <section className="portal-card" id="editorial-console" {...panelProps('editorial-console')}><header><div><span className="portal-step">Editorial</span><h3>Biography and photo review</h3></div><p>Original submissions remain preserved; approval requires current consent.</p></header><div className="review-stack">{biographies.filter((item) => item.profile_id !== userId && item.editorial_status !== 'draft').map((item) => <form key={item.id} onSubmit={(event) => void reviewBiography(event, item.id)}><strong>{displayPerson(allPeople.find((person) => person.id === item.profile_id), item.profile_id)}</strong><p>{item.submitted_text || item.original_text}</p><label>Edited version<textarea name="edited_text" defaultValue={item.edited_text || item.submitted_text || ''} /></label><label>Editor note<input name="editor_note" defaultValue={item.editor_note || ''} /></label><label>Decision<select name="status" defaultValue="edited"><option value="revision_requested">Request revision</option><option value="edited">Edited—member review</option>{item.editorial_status === 'member_approved' && <option value="publication_approved">Approve publication</option>}</select></label><button type="submit">Save review</button></form>)}</div><div className="review-stack">{media.filter((asset) => asset.uploader_profile_id !== userId && asset.moderation_status !== 'private').map((asset) => <form key={asset.id} onSubmit={(event) => void reviewMedia(event, asset.id)}><strong>{displayPerson(allPeople.find((person) => person.id === asset.uploader_profile_id), asset.uploader_profile_id)} · {asset.media_type.replaceAll('_', ' ')}</strong><p>{asset.caption || 'No caption'}</p><button type="button" onClick={() => void viewMedia(asset)}>Preview</button><label>Decision<select name="status" defaultValue="approved"><option value="revision_requested">Request revision</option><option value="approved">Approve</option><option value="rejected">Reject</option></select></label><label>Reviewer note<input name="reviewer_note" /></label><label><input type="checkbox" name="book_approved" /> Include in book when consented</label><label><input type="checkbox" name="public_gallery_approved" /> Approve for future gallery</label><button type="submit">Save moderation</button></form>)}</div><button className="portal-button" type="button" onClick={() => void generateBookExport()}>Generate consent-filtered book manifest</button></section>}

      {administrator && <section className="portal-card" id="access-management" {...panelProps('access-management')}><header><div><span className="portal-step">Access</span><h3>Roles, representatives, and committees</h3></div><p>Use Invitation Manager for people who may invite others without broader administrator access.</p></header><div className="admin-grid"><form onSubmit={assignRole}><h4>Role management</h4><label>Member<select name="profile_id" required><option value="">Choose</option>{profiles.map((person) => <option key={person.id} value={person.id}>{displayPerson(person)} · {person.email_private}</option>)}</select></label><label>Role<select name="role">{ROLE_OPTIONS.map((role) => <option key={role}>{role}</option>)}</select></label><label>Action<select name="mode"><option value="grant">Grant</option><option value="revoke">Revoke</option></select></label><button type="submit">Update role</button></form><form onSubmit={assignCommittee}><h4>Committee membership</h4><label>Member<select name="profile_id" required>{profiles.map((person) => <option key={person.id} value={person.id}>{displayPerson(person)}</option>)}</select></label><label>Committee<select name="committee_id" required>{committees.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label>Committee role<select name="committee_role"><option>member</option><option>lead</option><option>deputy</option><option>india_coordinator</option><option>finance_liaison</option></select></label><button type="submit">Assign</button></form><form onSubmit={assignDepartmentRepresentative}><h4>Department representative</h4><label>Member<select name="profile_id" required>{profiles.map((person) => <option key={person.id} value={person.id}>{displayPerson(person)}</option>)}</select></label><label>Department<select name="department_id" required>{departments.map((item) => <option key={item.id} value={item.id}>{item.code} · {item.name}</option>)}</select></label><label><input type="checkbox" name="india" /> India-based coordinator</label><button type="submit">Assign representative</button></form><form onSubmit={createDepartment}><h4>Add department</h4><label>Code<input name="code" pattern="[A-Za-z0-9-]{2,12}" required /></label><label>Name<input name="name" required /></label><button type="submit">Create department</button></form></div></section>}

      <section className="portal-card" id="event-program" {...panelProps('event-program')}><header><div><span className="portal-step">Event</span><h3>Program and volunteer shifts</h3></div><p>Confirmed event details and your operational assignments.</p></header><div className="timeline-list">{program.map((item) => <article key={item.id}><time>{new Date(item.starts_at).toLocaleString()}</time><strong>{item.title}</strong><span>{item.venue || 'Venue pending'}</span></article>)}</div><div className="workspace-list">{shifts.map((item) => <article key={item.id}><div><strong>{item.title}</strong><p>{new Date(item.starts_at).toLocaleString()} · {item.location || 'Location pending'} · {item.required_volunteers} needed</p></div><span className={`status-pill status-pill--${item.status}`}>{item.status}</span></article>)}</div></section>

      {eventOperator && <section className="portal-card" id="event-operations" {...panelProps('event-operations')}><header><div><span className="portal-step">Operations</span><h3>Event-day controls</h3></div><p>Faculty invitations, program, shifts, and mobile check-in.</p></header>{eventDashboard && <dl className="summary-grid">{Object.entries(eventDashboard).map(([label, value]) => <div key={label}><dt>{label.replaceAll('_', ' ')}</dt><dd>{value}</dd></div>)}</dl>}<div className="admin-grid"><form onSubmit={addFaculty}><h4>Add faculty or staff</h4><label>Name<input name="full_name" required /></label><label>Affiliation<input name="affiliation" /></label><button type="submit">Add</button></form><form onSubmit={createProgramItem}><h4>Add program item</h4><label>Title<input name="title" required /></label><label>Starts<input name="starts_at" type="datetime-local" required /></label><label>Ends<input name="ends_at" type="datetime-local" required /></label><label>Venue<input name="venue" /></label><label><input name="is_public" type="checkbox" /> Public program</label><button type="submit">Create</button></form><form onSubmit={createShift}><h4>Add volunteer shift</h4><label>Title<input name="title" required /></label><label>Starts<input name="starts_at" type="datetime-local" required /></label><label>Ends<input name="ends_at" type="datetime-local" required /></label><label>Location<input name="location" /></label><label>Volunteers needed<input name="required_volunteers" type="number" min="1" max="100" defaultValue="1" /></label><button type="submit">Create shift</button></form><form onSubmit={checkIn}><h4>Check in attendee</h4><label>Attendee<select name="target" required><option value="">Choose</option>{profiles.map((person) => <option key={person.id} value={`profile:${person.id}`}>{displayPerson(person)}</option>)}{faculty.map((person) => <option key={person.id} value={`faculty:${person.id}`}>{person.full_name} · faculty/staff</option>)}</select></label><label>Adults<input name="party_adults" type="number" min="0" max="10" defaultValue="1" /></label><label>Children<input name="party_children" type="number" min="0" max="20" defaultValue="0" /></label><button type="submit">Check in</button></form></div></section>}

      <section className="portal-card" id="feedback-privacy" {...panelProps('feedback-privacy')}><header><div><span className="portal-step">Support</span><h3>Feedback and privacy requests</h3></div><p>Report issues, suggest improvements, or exercise your data rights.</p></header><div className="admin-grid"><form onSubmit={submitFeedback}><h4>Send feedback</h4><label>Category<select name="category"><option>general</option><option>bug</option><option>idea</option><option>accessibility</option><option>privacy</option><option>event</option></select></label><label>Message<textarea name="message" required minLength={5} /></label><button type="submit">Submit feedback</button></form><form onSubmit={submitDataRequest}><h4>Privacy request</h4><label>Request<select name="request_type"><option value="access">Access my data</option><option value="correction">Correct my data</option><option value="export">Export my data</option><option value="withdraw_publication">Withdraw publication</option><option value="delete_account">Delete my account</option></select></label><label>Details<textarea name="details" /></label><button type="submit">Submit request</button></form></div></section>
      <AdminOperations userId={userId} roles={roles} people={allPeople} departments={departments} shifts={shifts} activeSection={activeSection} />
    </>
  )
}
