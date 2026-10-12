-- Phase 3: private directory, department outreach, committees, tasks,
-- announcements, organizer dashboards, and delegated invitation managers.

alter table public.user_roles drop constraint user_roles_role_name_check;
alter table public.user_roles add constraint user_roles_role_name_check check (
  role_name in (
    'member', 'department_rep', 'committee_lead', 'editor', 'admin', 'finance',
    'auditor', 'technical_admin', 'invitation_manager', 'event_operator'
  )
);

alter table public.profiles
  add column graduation_batch text not null default '1998–2002',
  add column directory_summary text check (directory_summary is null or char_length(directory_summary) <= 280);

create table public.committees (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{3,80}$'),
  name text not null unique,
  purpose text not null,
  responsibilities text,
  deliverables text,
  meeting_frequency text,
  status text not null default 'planning' check (status in ('planning', 'active', 'paused', 'complete', 'archived')),
  requires_india_coordinator boolean not null default false,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.committee_members (
  id uuid primary key default gen_random_uuid(),
  committee_id uuid not null references public.committees(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  committee_role text not null default 'member' check (
    committee_role in ('lead', 'deputy', 'india_coordinator', 'finance_liaison', 'member')
  ),
  active boolean not null default true,
  assigned_by uuid references auth.users(id),
  assigned_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (committee_id, profile_id)
);

create table public.contact_attempts (
  id uuid primary key default gen_random_uuid(),
  department_id uuid not null references public.departments(id),
  profile_id uuid references public.profiles(id) on delete set null,
  invitation_id uuid references public.invitations(id) on delete set null,
  alumni_name text not null check (char_length(trim(alumni_name)) between 2 and 160),
  status text not null default 'not_started' check (
    status in ('not_started', 'attempted', 'reached', 'invited', 'declined', 'invalid_contact')
  ),
  notes_private text check (notes_private is null or char_length(notes_private) <= 1000),
  last_contacted_at timestamptz,
  recorded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  task_number bigint generated always as identity unique,
  committee_id uuid not null references public.committees(id),
  owner_profile_id uuid references public.profiles(id) on delete set null,
  title text not null check (char_length(trim(title)) between 3 and 180),
  description text not null default '',
  priority text not null default 'medium' check (priority in ('low', 'medium', 'high', 'critical')),
  status text not null default 'proposed' check (
    status in ('proposed', 'ready', 'in_progress', 'blocked', 'completed', 'cancelled')
  ),
  start_date date,
  due_date date,
  progress_note text,
  organizer_comments text,
  relevant_link text,
  cancellation_reason text,
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  check (due_date is null or start_date is null or due_date >= start_date),
  check ((status = 'completed') = (completed_at is not null)),
  check (status <> 'cancelled' or nullif(trim(cancellation_reason), '') is not null)
);

create table public.task_assignees (
  task_id uuid not null references public.tasks(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  assignment_role text not null default 'support' check (assignment_role in ('owner', 'support')),
  assigned_by uuid not null references auth.users(id),
  assigned_at timestamptz not null default now(),
  primary key (task_id, profile_id)
);

create table public.task_dependencies (
  task_id uuid not null references public.tasks(id) on delete cascade,
  blocking_task_id uuid not null references public.tasks(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (task_id, blocking_task_id),
  check (task_id <> blocking_task_id)
);

create table public.task_comments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  author_profile_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  organizer_only boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(trim(title)) between 3 and 180),
  body text not null check (char_length(trim(body)) between 3 and 5000),
  status text not null default 'draft' check (status in ('draft', 'scheduled', 'published', 'archived')),
  audience_type text not null default 'all_members' check (
    audience_type in ('public', 'all_members', 'organizers', 'department', 'committee')
  ),
  audience_id uuid,
  pinned boolean not null default false,
  publish_at timestamptz,
  published_at timestamptz,
  author_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (audience_type in ('department', 'committee') and audience_id is not null)
    or (audience_type not in ('department', 'committee') and audience_id is null)
  )
);

create index tasks_committee_status_due_idx on public.tasks (committee_id, status, due_date);
create index tasks_owner_status_due_idx on public.tasks (owner_profile_id, status, due_date);
create index announcements_publication_idx on public.announcements (status, publish_at, pinned);
create index contact_attempts_department_status_idx on public.contact_attempts (department_id, status);

create trigger committees_touch_updated_at before update on public.committees
for each row execute function private.touch_updated_at();
create trigger committee_members_touch_updated_at before update on public.committee_members
for each row execute function private.touch_updated_at();
create trigger contact_attempts_touch_updated_at before update on public.contact_attempts
for each row execute function private.touch_updated_at();
create trigger task_comments_touch_updated_at before update on public.task_comments
for each row execute function private.touch_updated_at();
create trigger announcements_touch_updated_at before update on public.announcements
for each row execute function private.touch_updated_at();

create or replace function private.is_committee_lead(target_user uuid, target_committee uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.committee_members
    where committee_id = target_committee
      and profile_id = target_user
      and committee_role in ('lead', 'deputy')
      and active
  );
$$;

create or replace function private.can_invite(target_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_admin(target_user)
    or private.has_role(target_user, 'invitation_manager');
$$;

revoke all on function private.is_committee_lead(uuid, uuid) from public;
revoke all on function private.can_invite(uuid) from public;
grant execute on function private.is_committee_lead(uuid, uuid) to authenticated;
grant execute on function private.can_invite(uuid) to authenticated;

-- Delegated invitation managers can create invitations but receive no other
-- administrator capability.
create or replace function public.create_invitation(
  p_email text,
  p_full_name text,
  p_department_id uuid default null,
  p_expires_days integer default 14
)
returns table (invitation_id uuid, invitation_token text, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare raw_token text; new_id uuid; expiry timestamptz;
begin
  if not private.can_invite((select auth.uid())) then raise exception 'Invitation manager access required'; end if;
  if p_email !~* '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'A valid email address is required'; end if;
  if char_length(trim(p_full_name)) not between 2 and 160 then raise exception 'A valid full name is required'; end if;
  if p_expires_days not between 1 and 30 then raise exception 'Invitation expiry must be between 1 and 30 days'; end if;
  raw_token := encode(extensions.gen_random_bytes(24), 'hex');
  expiry := now() + make_interval(days => p_expires_days);
  insert into public.invitations (email, full_name, department_id, token_hash, expires_at, created_by)
  values (lower(trim(p_email)), trim(p_full_name), p_department_id,
    encode(extensions.digest(raw_token, 'sha256'), 'hex'), expiry, (select auth.uid()))
  returning id into new_id;
  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), 'invitation.created', 'invitation', new_id::text,
    jsonb_build_object('department_id', p_department_id, 'expires_at', expiry));
  return query select new_id, raw_token, expiry;
end;
$$;

create or replace function private.validate_task_state()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status = 'completed' and new.completed_at is null then new.completed_at := now(); end if;
  if new.status <> 'completed' then new.completed_at := null; end if;
  if new.status = 'cancelled' and nullif(trim(new.cancellation_reason), '') is null then
    raise exception 'Cancelled tasks require a reason';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
create trigger tasks_validate_state before insert or update on public.tasks
for each row execute function private.validate_task_state();

create or replace function private.prevent_task_dependency_cycle()
returns trigger language plpgsql set search_path = '' as $$
begin
  if exists (
    with recursive chain(task_id) as (
      select new.blocking_task_id
      union all
      select dependency.blocking_task_id
      from public.task_dependencies dependency
      join chain on dependency.task_id = chain.task_id
    )
    select 1 from chain where task_id = new.task_id
  ) then raise exception 'Task dependency cycle is not allowed'; end if;
  return new;
end;
$$;
create trigger task_dependencies_prevent_cycle before insert or update on public.task_dependencies
for each row execute function private.prevent_task_dependency_cycle();

create or replace function public.create_task(
  p_committee_id uuid, p_title text, p_description text default '',
  p_owner_profile_id uuid default null, p_priority text default 'medium',
  p_status text default 'ready', p_due_date date default null
)
returns public.tasks language plpgsql security definer set search_path = '' as $$
declare created_task public.tasks;
begin
  if not (private.is_admin((select auth.uid())) or private.is_committee_lead((select auth.uid()), p_committee_id)) then
    raise exception 'Committee lead or administrator access required';
  end if;
  insert into public.tasks (committee_id, owner_profile_id, title, description, priority, status, due_date, created_by, updated_by)
  values (p_committee_id, p_owner_profile_id, trim(p_title), coalesce(p_description, ''), p_priority, p_status,
    p_due_date, (select auth.uid()), (select auth.uid())) returning * into created_task;
  if p_owner_profile_id is not null then
    insert into public.task_assignees (task_id, profile_id, assignment_role, assigned_by)
    values (created_task.id, p_owner_profile_id, 'owner', (select auth.uid()));
  end if;
  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), 'task.created', 'task', created_task.id::text,
    jsonb_build_object('committee_id', p_committee_id, 'owner_profile_id', p_owner_profile_id));
  return created_task;
end;
$$;

create or replace function public.update_task_progress(
  p_task_id uuid, p_status text, p_progress_note text default null
)
returns public.tasks language plpgsql security definer set search_path = '' as $$
declare target public.tasks; updated_task public.tasks;
begin
  select * into target from public.tasks where id = p_task_id for update;
  if target.id is null then raise exception 'Task not found'; end if;
  if not (
    private.is_admin((select auth.uid()))
    or private.is_committee_lead((select auth.uid()), target.committee_id)
    or target.owner_profile_id = (select auth.uid())
    or exists (select 1 from public.task_assignees where task_id = target.id and profile_id = (select auth.uid()))
  ) then raise exception 'Task assignment required'; end if;
  if p_status not in ('ready', 'in_progress', 'blocked', 'completed') then raise exception 'Invalid progress status'; end if;
  update public.tasks set status = p_status, progress_note = nullif(trim(p_progress_note), ''),
    updated_by = (select auth.uid()) where id = p_task_id returning * into updated_task;
  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), 'task.progress_changed', 'task', p_task_id::text,
    jsonb_build_object('from', target.status, 'to', p_status));
  return updated_task;
end;
$$;

create or replace function public.set_committee_member(
  p_committee_id uuid, p_profile_id uuid, p_committee_role text, p_active boolean default true
)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_admin((select auth.uid())) then raise exception 'Administrator access required'; end if;
  if p_committee_role not in ('lead', 'deputy', 'india_coordinator', 'finance_liaison', 'member') then raise exception 'Invalid committee role'; end if;
  insert into public.committee_members (committee_id, profile_id, committee_role, active, assigned_by)
  values (p_committee_id, p_profile_id, p_committee_role, p_active, (select auth.uid()))
  on conflict (committee_id, profile_id) do update set committee_role = excluded.committee_role,
    active = excluded.active, assigned_by = excluded.assigned_by, updated_at = now();
  if p_committee_role = 'lead' and p_active then
    insert into public.user_roles (profile_id, role_name, granted_by)
    values (p_profile_id, 'committee_lead', (select auth.uid())) on conflict do nothing;
  end if;
  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), 'committee.membership_changed', 'committee', p_committee_id::text,
    jsonb_build_object('profile_id', p_profile_id, 'role', p_committee_role, 'active', p_active));
end;
$$;

create or replace function public.set_user_role(p_profile_id uuid, p_role text, p_enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_admin((select auth.uid())) then raise exception 'Administrator access required'; end if;
  if p_role not in (
    'member', 'department_rep', 'committee_lead', 'editor', 'admin', 'finance',
    'auditor', 'technical_admin', 'invitation_manager', 'event_operator'
  ) then raise exception 'Invalid role'; end if;
  if p_role in ('admin', 'technical_admin') and not private.has_role((select auth.uid()), 'technical_admin') then
    raise exception 'Technical administrator access required for privileged roles';
  end if;
  if p_enabled then
    insert into public.user_roles (profile_id, role_name, granted_by)
    values (p_profile_id, p_role, (select auth.uid())) on conflict (profile_id, role_name) do nothing;
  else
    if p_profile_id = (select auth.uid()) and p_role = 'technical_admin' then
      raise exception 'A technical administrator cannot revoke their own technical access';
    end if;
    delete from public.user_roles where profile_id = p_profile_id and role_name = p_role;
  end if;
  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), case when p_enabled then 'role.granted' else 'role.revoked' end,
    'profile', p_profile_id::text, jsonb_build_object('role', p_role));
end;
$$;

create or replace function public.department_coverage()
returns table (
  department_id uuid, code text, name text, representative_count bigint,
  has_india_coordinator boolean, needs_attention boolean
)
language sql stable security definer set search_path = '' as $$
  select d.id, d.code, d.name, count(r.id), coalesce(bool_or(r.is_india_coordinator and r.active), false),
    count(r.id) filter (where r.active) < 2 or not coalesce(bool_or(r.is_india_coordinator and r.active), false)
  from public.departments d
  left join public.department_representatives r on r.department_id = d.id and r.active
  where d.active and (
    private.is_admin((select auth.uid()))
    or private.has_role((select auth.uid()), 'department_rep')
  )
  group by d.id, d.code, d.name
  order by d.code;
$$;

create or replace function public.member_directory(p_query text default '')
returns table (
  profile_id uuid, display_name text, department_code text, city text,
  state_region text, country text, professional_field text, directory_summary text
)
language sql stable security definer set search_path = '' as $$
  select p.id, coalesce(p.preferred_name, p.full_name), d.code, p.city, p.state_region,
    p.country, p.professional_field, p.directory_summary
  from public.profiles p
  left join public.departments d on d.id = p.department_id
  where p.verification_status = 'verified'
    and exists (select 1 from public.consents c where c.profile_id = p.id and c.consent_type = 'directory_visibility' and c.granted)
    and (private.is_active_user((select auth.uid())) or private.is_admin((select auth.uid())))
    and (coalesce(trim(p_query), '') = '' or coalesce(p.preferred_name, p.full_name) ilike '%' || trim(p_query) || '%'
      or d.code ilike '%' || trim(p_query) || '%')
  order by d.code nulls last, coalesce(p.preferred_name, p.full_name);
$$;

create or replace function public.organizer_dashboard()
returns jsonb language sql stable security definer set search_path = '' as $$
  select case when private.is_admin((select auth.uid()))
    or private.has_role((select auth.uid()), 'committee_lead')
    or private.has_role((select auth.uid()), 'department_rep') then jsonb_build_object(
      'known_alumni', (select count(*) from public.invitations),
      'registered', (select count(*) from public.profiles),
      'verified', (select count(*) from public.profiles where verification_status = 'verified'),
      'committees_active', (select count(*) from public.committees where status = 'active'),
      'tasks_open', (select count(*) from public.tasks where status not in ('completed', 'cancelled')),
      'tasks_overdue', (select count(*) from public.tasks where due_date < current_date and status not in ('completed', 'cancelled')),
      'tasks_blocked', (select count(*) from public.tasks where status = 'blocked'),
      'tasks_unassigned', (select count(*) from public.tasks where owner_profile_id is null and status not in ('completed', 'cancelled'))
    ) else null end;
$$;

alter table public.committees enable row level security;
alter table public.committee_members enable row level security;
alter table public.contact_attempts enable row level security;
alter table public.tasks enable row level security;
alter table public.task_assignees enable row level security;
alter table public.task_dependencies enable row level security;
alter table public.task_comments enable row level security;
alter table public.announcements enable row level security;

create policy "Active members read committees" on public.committees for select to authenticated
using (private.is_active_user((select auth.uid())));
create policy "Admins manage committees" on public.committees for all to authenticated
using (private.is_admin((select auth.uid()))) with check (private.is_admin((select auth.uid())));

create policy "Active members read committee rosters" on public.committee_members for select to authenticated
using (private.is_active_user((select auth.uid())));
create policy "Admins manage committee rosters" on public.committee_members for all to authenticated
using (private.is_admin((select auth.uid()))) with check (private.is_admin((select auth.uid())));

create policy "Scoped organizers manage contact attempts" on public.contact_attempts for all to authenticated
using (private.is_admin((select auth.uid())) or private.is_department_rep((select auth.uid()), department_id))
with check (private.is_admin((select auth.uid())) or private.is_department_rep((select auth.uid()), department_id));

create policy "Members read relevant tasks" on public.tasks for select to authenticated using (
  private.is_admin((select auth.uid()))
  or private.is_committee_lead((select auth.uid()), committee_id)
  or owner_profile_id = (select auth.uid())
  or exists (select 1 from public.task_assignees a where a.task_id = id and a.profile_id = (select auth.uid()))
  or exists (select 1 from public.committee_members m where m.committee_id = tasks.committee_id and m.profile_id = (select auth.uid()) and m.active)
);
create policy "Admins and leads manage tasks" on public.tasks for all to authenticated
using (private.is_admin((select auth.uid())) or private.is_committee_lead((select auth.uid()), committee_id))
with check (private.is_admin((select auth.uid())) or private.is_committee_lead((select auth.uid()), committee_id));

create policy "Relevant users read task assignments" on public.task_assignees for select to authenticated using (
  profile_id = (select auth.uid()) or private.is_admin((select auth.uid()))
  or exists (select 1 from public.tasks t where t.id = task_id and private.is_committee_lead((select auth.uid()), t.committee_id))
);
create policy "Admins and leads manage task assignments" on public.task_assignees for all to authenticated
using (private.is_admin((select auth.uid())) or exists (select 1 from public.tasks t where t.id = task_id and private.is_committee_lead((select auth.uid()), t.committee_id)))
with check (private.is_admin((select auth.uid())) or exists (select 1 from public.tasks t where t.id = task_id and private.is_committee_lead((select auth.uid()), t.committee_id)));

create policy "Relevant users read task dependencies" on public.task_dependencies for select to authenticated
using (exists (select 1 from public.tasks t where t.id = task_id));
create policy "Admins and leads manage task dependencies" on public.task_dependencies for all to authenticated
using (private.is_admin((select auth.uid())) or exists (select 1 from public.tasks t where t.id = task_id and private.is_committee_lead((select auth.uid()), t.committee_id)))
with check (private.is_admin((select auth.uid())) or exists (select 1 from public.tasks t where t.id = task_id and private.is_committee_lead((select auth.uid()), t.committee_id)));

create policy "Relevant users read task comments" on public.task_comments for select to authenticated using (
  author_profile_id = (select auth.uid()) or private.is_admin((select auth.uid()))
  or exists (select 1 from public.tasks t where t.id = task_id and (
    private.is_committee_lead((select auth.uid()), t.committee_id)
    or (not organizer_only and (t.owner_profile_id = (select auth.uid()) or exists (
      select 1 from public.task_assignees a where a.task_id = t.id and a.profile_id = (select auth.uid())
    )))
  ))
);
create policy "Task participants add comments" on public.task_comments for insert to authenticated with check (
  author_profile_id = (select auth.uid()) and exists (
    select 1 from public.tasks t where t.id = task_id and (
      private.is_admin((select auth.uid())) or private.is_committee_lead((select auth.uid()), t.committee_id)
      or t.owner_profile_id = (select auth.uid())
      or exists (select 1 from public.task_assignees a where a.task_id = t.id and a.profile_id = (select auth.uid()))
    )
  )
);

create policy "Public reads published public announcements" on public.announcements for select to anon using (
  status = 'published' and audience_type = 'public' and coalesce(publish_at, published_at, created_at) <= now()
);
create policy "Members read targeted announcements" on public.announcements for select to authenticated using (
  status = 'published' and coalesce(publish_at, published_at, created_at) <= now() and (
    audience_type in ('public', 'all_members')
    or (audience_type = 'organizers' and exists (select 1 from public.user_roles r where r.profile_id = (select auth.uid()) and r.role_name <> 'member'))
    or (audience_type = 'department' and audience_id = (select department_id from public.profiles where id = (select auth.uid())))
    or (audience_type = 'committee' and exists (select 1 from public.committee_members m where m.committee_id = audience_id and m.profile_id = (select auth.uid()) and m.active))
    or private.is_admin((select auth.uid()))
  )
);
create policy "Admins manage announcements" on public.announcements for all to authenticated
using (private.is_admin((select auth.uid()))) with check (private.is_admin((select auth.uid())));

grant select on public.committees, public.committee_members, public.tasks, public.task_assignees,
  public.task_dependencies, public.task_comments, public.announcements to authenticated;
grant select on public.announcements to anon;
grant select, insert, update, delete on public.contact_attempts to authenticated;
grant insert, update, delete on public.committees, public.committee_members, public.tasks,
  public.task_assignees, public.task_dependencies, public.task_comments, public.announcements to authenticated;
grant usage, select on sequence public.tasks_task_number_seq to authenticated;
grant execute on function public.create_task(uuid, text, text, uuid, text, text, date) to authenticated;
grant execute on function public.update_task_progress(uuid, text, text) to authenticated;
grant execute on function public.set_committee_member(uuid, uuid, text, boolean) to authenticated;
grant execute on function public.set_user_role(uuid, text, boolean) to authenticated;
grant execute on function public.department_coverage() to authenticated;
grant execute on function public.member_directory(text) to authenticated;
grant execute on function public.organizer_dashboard() to authenticated;
grant insert, update on public.departments to authenticated;
grant update (department_id, directory_summary) on public.profiles to authenticated;

insert into public.committees (slug, name, purpose, responsibilities, deliverables, meeting_frequency, status, requires_india_coordinator)
values
  ('registration-outreach', 'Registration & Alumni Outreach', 'Reconnect with classmates and maintain the verified batch roster.', 'Invitations, department coverage, contact attempts, RSVP follow-up', 'Verified roster and complete outreach log', 'Weekly', 'active', true),
  ('program-faculty', 'Program & Faculty Relations', 'Shape the reunion program and coordinate faculty participation.', 'Program design, faculty outreach, stage coordination', 'Approved three-day program and faculty roster', 'Biweekly', 'active', true),
  ('venue-travel', 'Venue, Travel & Hospitality', 'Coordinate campus, travel, accommodation, and welcome logistics.', 'Venue, hotel guidance, transport, guest welcome', 'Venue plan and travel guide', 'Weekly', 'active', true),
  ('food-family', 'Food & Family Experience', 'Plan inclusive meals and family experiences.', 'Menus, dietary needs, partner and child activities', 'Meal and family-experience plan', 'Biweekly', 'active', true),
  ('finance-sponsorship', 'Finance, Sponsorship & Procurement', 'Coordinate transparent budgeting, sponsorship, and purchasing.', 'Budget summaries, sponsor coordination, procurement', 'Approved budget and procurement log', 'Weekly', 'active', true),
  ('communications-media', 'Communications, Memories & Media', 'Keep the batch informed and preserve approved memories.', 'Announcements, biography and photo coordination, documentation', 'Communication calendar and approved archive', 'Weekly', 'active', false),
  ('csr-batch-gift', 'CSR & Batch Gift', 'Create a meaningful collective contribution from the batch.', 'CSR selection, batch gift planning, stakeholder coordination', 'Approved project and handover plan', 'Biweekly', 'active', true)
on conflict (slug) do nothing;

insert into public.app_settings (key, value, is_public)
values
  ('features.committees', 'true', false),
  ('features.tasks', 'true', false),
  ('features.managed_announcements', 'true', false),
  ('features.directory', 'true', false)
on conflict (key) do update set value = excluded.value, updated_at = now();
