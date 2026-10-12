-- Phases 6 and 7: event operations, notifications, feedback, controlled
-- operational summaries, data requests, retention policy, and archive mode.

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_profile_id uuid not null references public.profiles(id) on delete cascade,
  notification_type text not null check (notification_type in ('task_assignment', 'task_due', 'revision_request', 'announcement', 'rsvp', 'system')),
  title text not null check (char_length(trim(title)) between 1 and 180),
  body text not null default '' check (char_length(body) <= 1000),
  entity_type text,
  entity_id text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.faculty_staff (
  id uuid primary key default gen_random_uuid(),
  full_name text not null check (char_length(trim(full_name)) between 2 and 160),
  affiliation text,
  invite_status text not null default 'not_started' check (invite_status in ('not_started', 'contacted', 'invited', 'accepted', 'declined', 'unreachable')),
  attendance_status text not null default 'undecided' check (attendance_status in ('undecided', 'attending', 'not_attending')),
  contact_private text,
  notes_private text,
  invited_at timestamptz,
  responded_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.program_items (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(trim(title)) between 3 and 180),
  description text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  venue text,
  audience text not null default 'all' check (audience in ('all', 'alumni', 'families', 'faculty', 'organizers')),
  status text not null default 'draft' check (status in ('draft', 'confirmed', 'cancelled', 'complete')),
  is_public boolean not null default false,
  owner_profile_id uuid references public.profiles(id) on delete set null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table public.volunteer_shifts (
  id uuid primary key default gen_random_uuid(),
  program_item_id uuid references public.program_items(id) on delete set null,
  committee_id uuid references public.committees(id) on delete set null,
  title text not null check (char_length(trim(title)) between 3 and 180),
  description text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  location text,
  required_volunteers integer not null default 1 check (required_volunteers between 1 and 100),
  status text not null default 'open' check (status in ('open', 'filled', 'cancelled', 'complete')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table public.shift_assignments (
  shift_id uuid not null references public.volunteer_shifts(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  assignment_status text not null default 'assigned' check (assignment_status in ('assigned', 'confirmed', 'declined', 'completed')),
  assigned_by uuid not null references auth.users(id),
  assigned_at timestamptz not null default now(),
  primary key (shift_id, profile_id)
);

create table public.checkins (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete set null,
  faculty_staff_id uuid references public.faculty_staff(id) on delete set null,
  checked_in_at timestamptz not null default now(),
  party_adults integer not null default 1 check (party_adults between 0 and 10),
  party_children integer not null default 0 check (party_children between 0 and 20),
  notes_private text,
  checked_in_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  check (num_nonnulls(profile_id, faculty_staff_id) = 1),
  unique (profile_id),
  unique (faculty_staff_id)
);

create table public.operational_contacts (
  id uuid primary key default gen_random_uuid(),
  contact_type text not null check (contact_type in ('emergency', 'venue', 'transport', 'accommodation', 'vendor', 'medical', 'security')),
  display_name text not null,
  organization text,
  phone_private text,
  email_private text,
  notes_private text,
  active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.finance_summaries (
  id uuid primary key default gen_random_uuid(),
  label text not null,
  amount numeric(14,2) not null,
  currency text not null default 'INR' check (currency ~ '^[A-Z]{3}$'),
  summary_type text not null check (summary_type in ('budget', 'committed', 'received', 'spent', 'balance')),
  as_of_date date not null default current_date,
  approved_for_portal boolean not null default false,
  notes text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.feedback_submissions (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete set null,
  category text not null default 'general' check (category in ('general', 'bug', 'idea', 'accessibility', 'privacy', 'event')),
  message text not null check (char_length(trim(message)) between 5 and 3000),
  status text not null default 'new' check (status in ('new', 'reviewing', 'planned', 'resolved', 'closed')),
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.data_requests (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  request_type text not null check (request_type in ('access', 'correction', 'export', 'withdraw_publication', 'delete_account')),
  details text check (details is null or char_length(details) <= 3000),
  status text not null default 'submitted' check (status in ('submitted', 'reviewing', 'approved', 'completed', 'declined')),
  resolution_note text,
  resolved_by uuid references auth.users(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.retention_policies (
  data_category text primary key,
  retain_until date,
  action text not null check (action in ('review', 'anonymize', 'delete', 'archive_private', 'retain_consented')),
  rationale text not null,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  updated_at timestamptz not null default now()
);

create trigger faculty_staff_touch_updated_at before update on public.faculty_staff for each row execute function private.touch_updated_at();
create trigger program_items_touch_updated_at before update on public.program_items for each row execute function private.touch_updated_at();
create trigger volunteer_shifts_touch_updated_at before update on public.volunteer_shifts for each row execute function private.touch_updated_at();
create trigger operational_contacts_touch_updated_at before update on public.operational_contacts for each row execute function private.touch_updated_at();
create trigger finance_summaries_touch_updated_at before update on public.finance_summaries for each row execute function private.touch_updated_at();
create trigger feedback_touch_updated_at before update on public.feedback_submissions for each row execute function private.touch_updated_at();
create trigger data_requests_touch_updated_at before update on public.data_requests for each row execute function private.touch_updated_at();

create or replace function private.is_event_operator(target_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_admin(target_user) or private.has_role(target_user, 'event_operator');
$$;
revoke all on function private.is_event_operator(uuid) from public;
grant execute on function private.is_event_operator(uuid) to authenticated;

create or replace function private.notify_task_assignment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare task_title text;
begin
  select title into task_title from public.tasks where id = new.task_id;
  insert into public.notifications (recipient_profile_id, notification_type, title, body, entity_type, entity_id)
  values (new.profile_id, 'task_assignment', 'New task assignment', task_title, 'task', new.task_id::text);
  return new;
end;
$$;
create trigger task_assignment_notification after insert on public.task_assignees
for each row execute function private.notify_task_assignment();

create or replace function private.notify_shift_assignment()
returns trigger language plpgsql security definer set search_path = '' as $$
declare shift_title text;
begin
  select title into shift_title from public.volunteer_shifts where id = new.shift_id;
  insert into public.notifications (recipient_profile_id, notification_type, title, body, entity_type, entity_id)
  values (new.profile_id, 'task_assignment', 'New volunteer shift', shift_title, 'volunteer_shift', new.shift_id::text);
  return new;
end;
$$;
create trigger shift_assignment_notification after insert on public.shift_assignments
for each row execute function private.notify_shift_assignment();

create or replace function private.notify_editorial_change()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.editorial_status = 'revision_requested' and old.editorial_status <> new.editorial_status then
    insert into public.notifications (recipient_profile_id, notification_type, title, body, entity_type, entity_id)
    values (new.profile_id, 'revision_request', 'Biography revision requested', coalesce(new.editor_note, ''), 'biography', new.id::text);
  elsif new.editorial_status = 'edited' and old.editorial_status <> new.editorial_status then
    insert into public.notifications (recipient_profile_id, notification_type, title, body, entity_type, entity_id)
    values (new.profile_id, 'revision_request', 'Edited biography ready for approval', 'Review and approve the edited version.', 'biography', new.id::text);
  end if;
  return new;
end;
$$;
create trigger biography_editorial_notification after update of editorial_status on public.biographies
for each row execute function private.notify_editorial_change();

create or replace function public.mark_notification_read(p_notification_id uuid)
returns void language sql security definer set search_path = '' as $$
  update public.notifications set read_at = now()
  where id = p_notification_id and recipient_profile_id = (select auth.uid());
$$;

create or replace function public.check_in_attendee(
  p_profile_id uuid default null, p_faculty_staff_id uuid default null,
  p_party_adults integer default 1, p_party_children integer default 0, p_notes text default null
)
returns public.checkins language plpgsql security definer set search_path = '' as $$
declare result public.checkins;
begin
  if not private.is_event_operator((select auth.uid())) then raise exception 'Event operator access required'; end if;
  if num_nonnulls(p_profile_id, p_faculty_staff_id) <> 1 then raise exception 'Choose exactly one attendee'; end if;
  if p_profile_id is not null then
    insert into public.checkins (profile_id, party_adults, party_children, notes_private, checked_in_by)
    values (p_profile_id, p_party_adults, p_party_children, nullif(trim(p_notes), ''), (select auth.uid()))
    on conflict (profile_id) do update set checked_in_at = now(),
      party_adults = excluded.party_adults, party_children = excluded.party_children,
      notes_private = excluded.notes_private, checked_in_by = excluded.checked_in_by
    returning * into result;
  else
    insert into public.checkins (faculty_staff_id, party_adults, party_children, notes_private, checked_in_by)
    values (p_faculty_staff_id, p_party_adults, p_party_children, nullif(trim(p_notes), ''), (select auth.uid()))
    on conflict (faculty_staff_id) do update set checked_in_at = now(),
      party_adults = excluded.party_adults, party_children = excluded.party_children,
      notes_private = excluded.notes_private, checked_in_by = excluded.checked_in_by
    returning * into result;
  end if;
  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), 'attendee.checked_in', 'checkin', result.id::text,
    jsonb_build_object('profile_id', p_profile_id, 'faculty_staff_id', p_faculty_staff_id,
      'party_adults', p_party_adults, 'party_children', p_party_children));
  return result;
end;
$$;

create or replace function public.event_operations_dashboard()
returns jsonb language sql stable security definer set search_path = '' as $$
  select case when private.is_event_operator((select auth.uid())) then jsonb_build_object(
    'faculty_invited', (select count(*) from public.faculty_staff where invite_status in ('invited', 'accepted')),
    'faculty_attending', (select count(*) from public.faculty_staff where attendance_status = 'attending'),
    'program_confirmed', (select count(*) from public.program_items where status = 'confirmed'),
    'volunteer_shifts_open', (select count(*) from public.volunteer_shifts where status = 'open'),
    'volunteer_slots_needed', (select coalesce(sum(greatest(s.required_volunteers - coalesce(a.assigned, 0), 0)), 0)
      from public.volunteer_shifts s left join (
        select shift_id, count(*) assigned from public.shift_assignments where assignment_status <> 'declined' group by shift_id
      ) a on a.shift_id = s.id where s.status = 'open'),
    'alumni_checked_in', (select count(*) from public.checkins where profile_id is not null),
    'faculty_checked_in', (select count(*) from public.checkins where faculty_staff_id is not null),
    'adults_checked_in', (select coalesce(sum(party_adults), 0) from public.checkins),
    'children_checked_in', (select coalesce(sum(party_children), 0) from public.checkins)
  ) else null end;
$$;

create or replace function public.event_operator_profile_labels()
returns table (profile_id uuid, display_name text)
language sql stable security definer set search_path = '' as $$
  select p.id, coalesce(p.preferred_name, p.full_name)
  from public.profiles p
  where private.is_event_operator((select auth.uid())) and p.verification_status = 'verified'
  order by coalesce(p.preferred_name, p.full_name);
$$;

alter table public.notifications enable row level security;
alter table public.faculty_staff enable row level security;
alter table public.program_items enable row level security;
alter table public.volunteer_shifts enable row level security;
alter table public.shift_assignments enable row level security;
alter table public.checkins enable row level security;
alter table public.operational_contacts enable row level security;
alter table public.finance_summaries enable row level security;
alter table public.feedback_submissions enable row level security;
alter table public.data_requests enable row level security;
alter table public.retention_policies enable row level security;

create policy "Members read own notifications" on public.notifications for select to authenticated
using (recipient_profile_id = (select auth.uid()));
create policy "Members update own notifications" on public.notifications for update to authenticated
using (recipient_profile_id = (select auth.uid())) with check (recipient_profile_id = (select auth.uid()));

create policy "Event operators manage faculty" on public.faculty_staff for all to authenticated
using (private.is_event_operator((select auth.uid()))) with check (private.is_event_operator((select auth.uid())));

create policy "Public reads confirmed public program" on public.program_items for select to anon
using (status = 'confirmed' and is_public);
create policy "Members read confirmed program" on public.program_items for select to authenticated
using (status in ('confirmed', 'complete') or private.is_event_operator((select auth.uid())));
create policy "Event operators manage program" on public.program_items for all to authenticated
using (private.is_event_operator((select auth.uid()))) with check (private.is_event_operator((select auth.uid())));

create policy "Members read volunteer shifts" on public.volunteer_shifts for select to authenticated
using (private.is_active_user((select auth.uid())));
create policy "Event operators manage volunteer shifts" on public.volunteer_shifts for all to authenticated
using (private.is_event_operator((select auth.uid()))) with check (private.is_event_operator((select auth.uid())));
create policy "Members read own shift assignments" on public.shift_assignments for select to authenticated
using (profile_id = (select auth.uid()) or private.is_event_operator((select auth.uid())));
create policy "Event operators manage shift assignments" on public.shift_assignments for all to authenticated
using (private.is_event_operator((select auth.uid()))) with check (private.is_event_operator((select auth.uid())));

create policy "Event operators manage checkins" on public.checkins for all to authenticated
using (private.is_event_operator((select auth.uid()))) with check (private.is_event_operator((select auth.uid())));
create policy "Event operators read contacts" on public.operational_contacts for select to authenticated
using (private.is_event_operator((select auth.uid())));
create policy "Admins manage contacts" on public.operational_contacts for all to authenticated
using (private.is_admin((select auth.uid()))) with check (private.is_admin((select auth.uid())));

create policy "Finance roles read approved summaries" on public.finance_summaries for select to authenticated
using (approved_for_portal and (private.has_role((select auth.uid()), 'finance') or private.is_admin((select auth.uid()))));
create policy "Admins manage finance summaries" on public.finance_summaries for all to authenticated
using (private.is_admin((select auth.uid()))) with check (private.is_admin((select auth.uid())));

create policy "Members create feedback" on public.feedback_submissions for insert to authenticated
with check (profile_id = (select auth.uid()));
create policy "Members read own feedback" on public.feedback_submissions for select to authenticated
using (profile_id = (select auth.uid()) or private.is_admin((select auth.uid())));
create policy "Admins manage feedback" on public.feedback_submissions for all to authenticated
using (private.is_admin((select auth.uid()))) with check (private.is_admin((select auth.uid())));

create policy "Members manage own data requests" on public.data_requests for select to authenticated
using (profile_id = (select auth.uid()) or private.is_admin((select auth.uid())));
create policy "Members submit own data requests" on public.data_requests for insert to authenticated
with check (profile_id = (select auth.uid()));
create policy "Admins resolve data requests" on public.data_requests for update to authenticated
using (private.is_admin((select auth.uid()))) with check (private.is_admin((select auth.uid())));

create policy "Admins manage retention policy" on public.retention_policies for all to authenticated
using (private.is_admin((select auth.uid()))) with check (private.is_admin((select auth.uid())));
create policy "Auditors read retention policy" on public.retention_policies for select to authenticated
using (private.has_role((select auth.uid()), 'auditor'));

grant select on public.notifications, public.program_items, public.volunteer_shifts,
  public.shift_assignments, public.feedback_submissions, public.data_requests to authenticated;
grant update (read_at) on public.notifications to authenticated;
grant insert on public.feedback_submissions, public.data_requests to authenticated;
grant select, insert, update, delete on public.faculty_staff, public.checkins,
  public.operational_contacts, public.finance_summaries, public.retention_policies to authenticated;
grant insert, update, delete on public.program_items, public.volunteer_shifts, public.shift_assignments to authenticated;
grant select on public.program_items to anon;
grant execute on function public.mark_notification_read(uuid) to authenticated;
grant execute on function public.check_in_attendee(uuid, uuid, integer, integer, text) to authenticated;
grant execute on function public.event_operations_dashboard() to authenticated;
grant execute on function public.event_operator_profile_labels() to authenticated;

insert into public.retention_policies (data_category, retain_until, action, rationale)
values
  ('dietary_accessibility_notes', '2027-08-31', 'delete', 'Operationally sensitive notes are removed after event closeout.'),
  ('transport_accommodation_notes', '2027-08-31', 'delete', 'Travel logistics are not required after closeout.'),
  ('task_history', null, 'archive_private', 'Preserve organizing history for future reunion planning.'),
  ('unapproved_media', '2027-12-31', 'review', 'Give contributors time to resolve consent or moderation issues.'),
  ('approved_biographies_media', null, 'retain_consented', 'Retain only while current publication consent remains active.')
on conflict (data_category) do nothing;

insert into public.app_settings (key, value, is_public)
values
  ('features.event_operations', 'true', false),
  ('features.feedback', 'true', false),
  ('features.archive_mode', 'false', true),
  ('features.checkin', 'true', false),
  ('retention.last_reviewed', '"2026-10-11"', false)
on conflict (key) do update set value = excluded.value, updated_at = now();
