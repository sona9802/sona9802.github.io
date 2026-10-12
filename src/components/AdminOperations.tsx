import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { supabase } from '../lib/supabase'

type Person = { id: string; full_name: string; preferred_name?: string | null }
type Department = { id: string; code: string; name: string }
type Shift = { id: string; title: string }
type ContactAttempt = { id: string; alumni_name: string; status: string; department_id: string; last_contacted_at: string | null }
type OperationalContact = { id: string; contact_type: string; display_name: string; organization: string | null; phone_private: string | null; email_private: string | null }
type FinanceSummary = { id: string; label: string; amount: number; currency: string; summary_type: string; as_of_date: string }
type Feedback = { id: string; category: string; message: string; status: string; created_at: string }
type DataRequest = { id: string; request_type: string; details: string | null; status: string; created_at: string }
type RetentionPolicy = { data_category: string; retain_until: string | null; action: string; rationale: string }
type AuditEvent = { id: number; action: string; entity_type: string; entity_id: string | null; created_at: string }

type Props = {
  userId: string
  roles: string[]
  people: Person[]
  departments: Department[]
  shifts: Shift[]
}

export function AdminOperations({ userId, roles, people, departments, shifts }: Props) {
  const admin = roles.some((role) => ['admin', 'technical_admin'].includes(role))
  const organizer = admin || roles.includes('department_rep')
  const eventOperator = admin || roles.includes('event_operator')
  const finance = admin || roles.includes('finance')
  const auditor = admin || roles.includes('auditor')
  const [attempts, setAttempts] = useState<ContactAttempt[]>([])
  const [contacts, setContacts] = useState<OperationalContact[]>([])
  const [summaries, setSummaries] = useState<FinanceSummary[]>([])
  const [feedback, setFeedback] = useState<Feedback[]>([])
  const [requests, setRequests] = useState<DataRequest[]>([])
  const [retention, setRetention] = useState<RetentionPolicy[]>([])
  const [audit, setAudit] = useState<AuditEvent[]>([])
  const [message, setMessage] = useState<string | null>(null)

  const load = useCallback(async () => {
    if (!supabase) return
    const queries = []
    if (organizer) queries.push(supabase.from('contact_attempts').select('id,alumni_name,status,department_id,last_contacted_at').order('updated_at', { ascending: false }).limit(100).then(({ data }) => setAttempts((data ?? []) as ContactAttempt[])))
    if (eventOperator) queries.push(supabase.from('operational_contacts').select('id,contact_type,display_name,organization,phone_private,email_private').eq('active', true).order('contact_type').then(({ data }) => setContacts((data ?? []) as OperationalContact[])))
    if (finance) queries.push(supabase.from('finance_summaries').select('id,label,amount,currency,summary_type,as_of_date').order('as_of_date', { ascending: false }).then(({ data }) => setSummaries((data ?? []) as FinanceSummary[])))
    if (admin) {
      queries.push(supabase.from('feedback_submissions').select('id,category,message,status,created_at').order('created_at', { ascending: false }).limit(100).then(({ data }) => setFeedback((data ?? []) as Feedback[])))
      queries.push(supabase.from('data_requests').select('id,request_type,details,status,created_at').order('created_at', { ascending: false }).limit(100).then(({ data }) => setRequests((data ?? []) as DataRequest[])))
    }
    if (auditor) {
      queries.push(supabase.from('retention_policies').select('data_category,retain_until,action,rationale').order('data_category').then(({ data }) => setRetention((data ?? []) as RetentionPolicy[])))
      queries.push(supabase.from('audit_events').select('id,action,entity_type,entity_id,created_at').order('created_at', { ascending: false }).limit(100).then(({ data }) => setAudit((data ?? []) as AuditEvent[])))
    }
    await Promise.all(queries)
  }, [admin, auditor, eventOperator, finance, organizer])

  useEffect(() => { void load() }, [load])

  async function save(result: PromiseLike<{ error: { message: string } | null }>, success: string) {
    const { error } = await result
    setMessage(error ? error.message : success)
    if (!error) await load()
  }

  async function addAttempt(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    await save(supabase!.from('contact_attempts').insert({
      department_id: String(form.get('department_id')), alumni_name: String(form.get('alumni_name')),
      status: String(form.get('status')), notes_private: String(form.get('notes_private') ?? '') || null,
      last_contacted_at: form.get('status') === 'not_started' ? null : new Date().toISOString(), recorded_by: userId,
    }), 'Contact attempt saved.')
    event.currentTarget.reset()
  }

  async function assignShift(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    await save(supabase!.from('shift_assignments').upsert({
      shift_id: String(form.get('shift_id')), profile_id: String(form.get('profile_id')),
      assignment_status: 'assigned', assigned_by: userId,
    }), 'Volunteer assigned and notified.')
  }

  async function addOperationalContact(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    await save(supabase!.from('operational_contacts').insert({
      contact_type: String(form.get('contact_type')), display_name: String(form.get('display_name')),
      organization: String(form.get('organization') ?? '') || null, phone_private: String(form.get('phone_private') ?? '') || null,
      email_private: String(form.get('email_private') ?? '') || null, created_by: userId,
    }), 'Operational contact saved.')
    event.currentTarget.reset()
  }

  async function addFinanceSummary(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    await save(supabase!.from('finance_summaries').insert({
      label: String(form.get('label')), amount: Number(form.get('amount')), currency: String(form.get('currency')).toUpperCase(),
      summary_type: String(form.get('summary_type')), approved_for_portal: form.get('approved') === 'on', created_by: userId,
    }), 'Finance summary saved.')
    event.currentTarget.reset()
  }

  async function updateQueue(table: 'feedback_submissions' | 'data_requests', id: string, status: string) {
    const values = table === 'data_requests' && status === 'completed'
      ? { status, resolved_by: userId, resolved_at: new Date().toISOString() }
      : { status }
    await save(supabase!.from(table).update(values).eq('id', id), 'Queue status updated.')
  }

  if (!organizer && !eventOperator && !finance && !auditor) return null

  return <>
    {message && <p className="portal-message portal-message--info" role="status">{message}</p>}

    {organizer && <section className="portal-card" id="contact-outreach"><header><div><span className="portal-step">Outreach</span><h3>Alumni contact tracker</h3></div><p>Private departmental outreach history; never shown in the member directory.</p></header><form className="workspace-form" onSubmit={addAttempt}><label>Department<select name="department_id" required><option value="">Choose</option>{departments.map((item) => <option key={item.id} value={item.id}>{item.code} · {item.name}</option>)}</select></label><label>Alumni name<input name="alumni_name" required /></label><label>Status<select name="status"><option value="not_started">Not started</option><option value="attempted">Attempted</option><option value="reached">Reached</option><option value="invited">Invited</option><option value="declined">Declined</option><option value="invalid_contact">Invalid contact</option></select></label><label className="portal-span">Private note<textarea name="notes_private" /></label><button type="submit">Save outreach</button></form><div className="workspace-list">{attempts.map((item) => <article key={item.id}><div><strong>{item.alumni_name}</strong><p>{departments.find((department) => department.id === item.department_id)?.code || 'Department'} · {item.status.replaceAll('_', ' ')}</p></div><small>{item.last_contacted_at ? new Date(item.last_contacted_at).toLocaleDateString() : 'Not contacted'}</small></article>)}</div></section>}

    {eventOperator && <section className="portal-card" id="operations-directory"><header><div><span className="portal-step">Logistics</span><h3>Assignments and operational contacts</h3></div><p>Role-restricted event-day roster and emergency/vendor directory.</p></header><div className="admin-grid"><form onSubmit={assignShift}><h4>Assign volunteer</h4><label>Shift<select name="shift_id" required><option value="">Choose</option>{shifts.map((item) => <option key={item.id} value={item.id}>{item.title}</option>)}</select></label><label>Member<select name="profile_id" required><option value="">Choose</option>{people.map((item) => <option key={item.id} value={item.id}>{item.preferred_name || item.full_name}</option>)}</select></label><button type="submit">Assign</button></form>{admin && <form onSubmit={addOperationalContact}><h4>Add operational contact</h4><label>Type<select name="contact_type"><option>emergency</option><option>venue</option><option>transport</option><option>accommodation</option><option>vendor</option><option>medical</option><option>security</option></select></label><label>Name<input name="display_name" required /></label><label>Organization<input name="organization" /></label><label>Phone<input name="phone_private" /></label><label>Email<input name="email_private" type="email" /></label><button type="submit">Save contact</button></form>}</div><div className="card-grid">{contacts.map((item) => <article className="mini-card" key={item.id}><strong>{item.display_name}</strong><p>{item.contact_type} · {item.organization || 'Independent'}</p><small>{[item.phone_private, item.email_private].filter(Boolean).join(' · ')}</small></article>)}</div></section>}

    {finance && <section className="portal-card" id="finance-summary"><header><div><span className="portal-step">Finance</span><h3>Approved financial summary</h3></div><p>Read-only for finance roles; administrators control published summary entries.</p></header>{admin && <form className="workspace-form" onSubmit={addFinanceSummary}><label>Label<input name="label" required /></label><label>Amount<input name="amount" type="number" step="0.01" required /></label><label>Currency<input name="currency" defaultValue="INR" pattern="[A-Za-z]{3}" required /></label><label>Type<select name="summary_type"><option>budget</option><option>committed</option><option>received</option><option>spent</option><option>balance</option></select></label><label><input name="approved" type="checkbox" /> Approved for portal</label><button type="submit">Save summary</button></form>}<dl className="summary-grid">{summaries.map((item) => <div key={item.id}><dt>{item.label}</dt><dd>{new Intl.NumberFormat('en-IN', { style: 'currency', currency: item.currency }).format(item.amount)}</dd></div>)}</dl></section>}

    {admin && <section className="portal-card" id="admin-queues"><header><div><span className="portal-step">Service</span><h3>Feedback and privacy queues</h3></div><p>Resolve member requests with status history and accountable ownership.</p></header><div className="review-stack">{feedback.map((item) => <article key={item.id}><strong>{item.category} · {item.status}</strong><p>{item.message}</p><select value={item.status} onChange={(event) => void updateQueue('feedback_submissions', item.id, event.target.value)}><option>new</option><option>reviewing</option><option>planned</option><option>resolved</option><option>closed</option></select></article>)}{requests.map((item) => <article key={item.id}><strong>Privacy: {item.request_type.replaceAll('_', ' ')} · {item.status}</strong><p>{item.details || 'No additional details.'}</p><select value={item.status} onChange={(event) => void updateQueue('data_requests', item.id, event.target.value)}><option>submitted</option><option>reviewing</option><option>approved</option><option>completed</option><option>declined</option></select></article>)}</div></section>}

    {auditor && <section className="portal-card" id="audit-retention"><header><div><span className="portal-step">Governance</span><h3>Audit and retention</h3></div><p>Latest immutable administrative events and approved post-event data rules.</p></header><div className="card-grid">{retention.map((item) => <article className="mini-card" key={item.data_category}><strong>{item.data_category.replaceAll('_', ' ')}</strong><p>{item.action.replaceAll('_', ' ')} {item.retain_until ? `after ${item.retain_until}` : ''}</p><small>{item.rationale}</small></article>)}</div><div className="workspace-list">{audit.map((item) => <article key={item.id}><div><strong>{item.action}</strong><p>{item.entity_type}{item.entity_id ? ` · ${item.entity_id}` : ''}</p></div><small>{new Date(item.created_at).toLocaleString()}</small></article>)}</div></section>}
  </>
}
