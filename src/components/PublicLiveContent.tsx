import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'

type Announcement = { id: string; title: string; body: string; publish_at: string | null; created_at: string; pinned: boolean }
type ProgramItem = { id: string; title: string; description: string | null; starts_at: string; ends_at: string; venue: string | null }

export function PublicLiveContent() {
  const [announcements, setAnnouncements] = useState<Announcement[]>([])
  const [program, setProgram] = useState<ProgramItem[]>([])

  useEffect(() => {
    if (!supabase) return
    void Promise.all([
      supabase.from('announcements').select('id,title,body,publish_at,created_at,pinned').eq('status', 'published').eq('audience_type', 'public').order('pinned', { ascending: false }).order('publish_at', { ascending: false }),
      supabase.from('program_items').select('id,title,description,starts_at,ends_at,venue').eq('status', 'confirmed').eq('is_public', true).order('starts_at'),
    ]).then(([announcementResult, programResult]) => {
      setAnnouncements((announcementResult.data ?? []) as Announcement[])
      setProgram((programResult.data ?? []) as ProgramItem[])
    })
  }, [])

  if (announcements.length === 0 && program.length === 0) return null

  return (
    <section className="section live-content" aria-labelledby="live-content-title">
      <div className="section-heading section-heading--split">
        <div><p className="section-kicker">Live from the portal</p><h2 id="live-content-title">Confirmed <em>updates.</em></h2></div>
        <p>These items are published by authorized reunion administrators and update without a website deployment.</p>
      </div>
      {announcements.length > 0 && <div className="announcement-list">{announcements.map((item) => <article key={item.id}><div><span>{item.pinned ? 'Pinned update' : 'Portal update'}</span><time>{new Date(item.publish_at || item.created_at).toLocaleDateString()}</time></div><h3>{item.title}</h3><p>{item.body}</p></article>)}</div>}
      {program.length > 0 && <div className="public-schedule">{program.map((item) => <article key={item.id}><time>{new Date(item.starts_at).toLocaleString()}</time><div><h3>{item.title}</h3><p>{item.description || 'Details confirmed by the organizing team.'}</p></div><strong>{item.venue || 'Venue to be confirmed'}</strong></article>)}</div>}
    </section>
  )
}
