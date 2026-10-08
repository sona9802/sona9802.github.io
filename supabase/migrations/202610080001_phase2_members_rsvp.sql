-- Phase 2: invitation-gated member profiles, roles, RSVP, consent, and audit foundations.
create extension if not exists citext with schema extensions;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9-]{2,12}$'),
  name text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  email extensions.citext not null,
  full_name text not null check (char_length(trim(full_name)) between 2 and 160),
  department_id uuid references public.departments(id),
  token_hash text not null unique,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'expired', 'revoked')),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  accepted_by uuid references auth.users(id),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status = 'accepted') = (accepted_at is not null and accepted_by is not null))
);

create unique index invitations_one_pending_per_email
  on public.invitations (lower(email::text))
  where status = 'pending';

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  department_id uuid references public.departments(id),
  email_private extensions.citext not null,
  full_name text not null check (char_length(trim(full_name)) between 2 and 160),
  preferred_name text check (preferred_name is null or char_length(trim(preferred_name)) between 1 and 80),
  city text,
  state_region text,
  country text,
  phone_private text,
  whatsapp_private text,
  professional_field text,
  willing_to_volunteer boolean not null default false,
  contact_visibility text not null default 'private' check (contact_visibility in ('private', 'batch')),
  verification_status text not null default 'pending' check (verification_status in ('invited', 'pending', 'verified', 'rejected', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  role_name text not null check (role_name in ('member', 'department_rep', 'committee_lead', 'editor', 'admin', 'finance', 'auditor', 'technical_admin')),
  granted_by uuid references auth.users(id),
  granted_at timestamptz not null default now(),
  unique (profile_id, role_name)
);

create table public.rsvps (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null unique references public.profiles(id) on delete cascade,
  attendance_status text not null default 'undecided' check (attendance_status in ('undecided', 'attending', 'not_attending')),
  arrival_date date,
  departure_date date,
  alumni_count integer not null default 1 check (alumni_count between 0 and 1),
  spouse_count integer not null default 0 check (spouse_count between 0 and 1),
  child_count integer not null default 0 check (child_count between 0 and 10),
  child_age_bands jsonb not null default '[]'::jsonb check (jsonb_typeof(child_age_bands) = 'array'),
  dietary_notes_private text,
  accessibility_notes_private text,
  accommodation_interest boolean not null default false,
  transport_interest boolean not null default false,
  optional_activity_interest boolean not null default false,
  organizer_notes_private text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (departure_date is null or arrival_date is null or departure_date >= arrival_date)
);

create table public.consents (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  consent_type text not null check (consent_type in ('directory_visibility', 'biography_publication', 'profile_photo_publication', 'reunion_photo_publication', 'book_publication')),
  policy_version text not null default '2026-10-provisional',
  granted boolean not null default false,
  decision_source text not null default 'onboarding' check (decision_source in ('onboarding', 'profile', 'admin_correction', 'withdrawal')),
  recorded_at timestamptz not null default now(),
  unique (profile_id, consent_type)
);

create table public.department_representatives (
  id uuid primary key default gen_random_uuid(),
  department_id uuid not null references public.departments(id),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  is_india_coordinator boolean not null default false,
  active boolean not null default true,
  assigned_by uuid references auth.users(id),
  assigned_at timestamptz not null default now(),
  unique (department_id, profile_id)
);

create table public.audit_events (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id),
  action text not null,
  entity_type text not null,
  entity_id text not null,
  summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger departments_touch_updated_at before update on public.departments
for each row execute function private.touch_updated_at();
create trigger invitations_touch_updated_at before update on public.invitations
for each row execute function private.touch_updated_at();
create trigger profiles_touch_updated_at before update on public.profiles
for each row execute function private.touch_updated_at();
create trigger rsvps_touch_updated_at before update on public.rsvps
for each row execute function private.touch_updated_at();

create or replace function private.has_role(target_user uuid, target_role text)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1
    from public.user_roles
    where profile_id = target_user and role_name = target_role
  );
$$;

create or replace function private.is_admin(target_user uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select private.has_role(target_user, 'admin') or private.has_role(target_user, 'technical_admin');
$$;

create or replace function private.is_active_user(target_user uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = target_user and verification_status in ('invited', 'pending', 'verified')
  );
$$;

create or replace function private.is_department_rep(target_user uuid, target_department uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.department_representatives
    where profile_id = target_user
      and department_id = target_department
      and active
  );
$$;

revoke all on function private.has_role(uuid, text) from public;
revoke all on function private.is_admin(uuid) from public;
revoke all on function private.is_active_user(uuid) from public;
revoke all on function private.is_department_rep(uuid, uuid) from public;
grant execute on function private.has_role(uuid, text) to authenticated;
grant execute on function private.is_admin(uuid) to authenticated;
grant execute on function private.is_active_user(uuid) to authenticated;
grant execute on function private.is_department_rep(uuid, uuid) to authenticated;

alter table public.departments enable row level security;
alter table public.invitations enable row level security;
alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.rsvps enable row level security;
alter table public.consents enable row level security;
alter table public.department_representatives enable row level security;
alter table public.audit_events enable row level security;

create policy "Active departments are public"
  on public.departments for select
  to anon, authenticated
  using (active);
create policy "Admins manage departments"
  on public.departments for all
  to authenticated
  using (private.is_admin((select auth.uid())))
  with check (private.is_admin((select auth.uid())));

create policy "Admins read invitations"
  on public.invitations for select
  to authenticated
  using (private.is_admin((select auth.uid())));

create policy "Profiles have scoped read access"
  on public.profiles for select
  to authenticated
  using (
    private.is_active_user((select auth.uid())) and (
      id = (select auth.uid())
      or private.is_admin((select auth.uid()))
      or (
        verification_status in ('invited', 'pending', 'verified')
        and private.is_department_rep((select auth.uid()), department_id)
      )
    )
  );
create policy "Members update their own profile"
  on public.profiles for update
  to authenticated
  using (id = (select auth.uid()) and private.is_active_user((select auth.uid())))
  with check (id = (select auth.uid()) and private.is_active_user((select auth.uid())));

create policy "Users read their own roles and admins read all roles"
  on public.user_roles for select
  to authenticated
  using (profile_id = (select auth.uid()) or private.is_admin((select auth.uid())));

create policy "RSVPs have scoped read access"
  on public.rsvps for select
  to authenticated
  using (
    private.is_active_user((select auth.uid())) and (
      profile_id = (select auth.uid())
      or private.is_admin((select auth.uid()))
      or exists (
        select 1 from public.profiles p
        where p.id = rsvps.profile_id
          and p.verification_status in ('invited', 'pending', 'verified')
          and private.is_department_rep((select auth.uid()), p.department_id)
      )
    )
  );
create policy "Members create their own RSVP"
  on public.rsvps for insert
  to authenticated
  with check (profile_id = (select auth.uid()) and private.is_active_user((select auth.uid())));
create policy "Members update their own RSVP"
  on public.rsvps for update
  to authenticated
  using (profile_id = (select auth.uid()) and private.is_active_user((select auth.uid())))
  with check (profile_id = (select auth.uid()) and private.is_active_user((select auth.uid())));

create policy "Users manage their own consent"
  on public.consents for all
  to authenticated
  using (profile_id = (select auth.uid()) and private.is_active_user((select auth.uid())))
  with check (profile_id = (select auth.uid()) and private.is_active_user((select auth.uid())));
create policy "Admins read consent"
  on public.consents for select
  to authenticated
  using (private.is_admin((select auth.uid())));

create policy "Representatives read their assignments"
  on public.department_representatives for select
  to authenticated
  using (profile_id = (select auth.uid()) or private.is_admin((select auth.uid())));

create policy "Authorized users read audit events"
  on public.audit_events for select
  to authenticated
  using (
    private.is_admin((select auth.uid()))
    or private.has_role((select auth.uid()), 'auditor')
  );

revoke all on public.departments, public.invitations, public.profiles, public.user_roles,
  public.rsvps, public.consents, public.department_representatives, public.audit_events
  from anon, authenticated;
grant select on public.departments to anon, authenticated;
grant select on public.invitations to authenticated;
grant select on public.profiles to authenticated;
grant update (preferred_name, city, state_region, country, phone_private, whatsapp_private,
  professional_field, willing_to_volunteer, contact_visibility) on public.profiles to authenticated;
grant select on public.user_roles to authenticated;
grant select, insert on public.rsvps to authenticated;
grant update (attendance_status, arrival_date, departure_date, alumni_count, spouse_count,
  child_count, child_age_bands, dietary_notes_private, accessibility_notes_private,
  accommodation_interest, transport_interest, optional_activity_interest) on public.rsvps to authenticated;
grant select, insert on public.consents to authenticated;
grant update (granted, policy_version, decision_source, recorded_at) on public.consents to authenticated;
grant select on public.department_representatives, public.audit_events to authenticated;

create or replace function public.accept_invitation(p_token text, p_preferred_name text default null)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  invite public.invitations;
  accepted_profile public.profiles;
  caller_email text;
  consent_name text;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  caller_email := lower(coalesce((select auth.jwt() ->> 'email'), ''));
  if caller_email = '' then
    raise exception 'Authenticated email is required';
  end if;

  select * into invite
  from public.invitations
  where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and status = 'pending'
    and expires_at > now()
  for update;

  if invite.id is null then
    raise exception 'Invitation is invalid or expired';
  end if;
  if lower(invite.email::text) <> caller_email then
    raise exception 'Invitation email does not match the signed-in account';
  end if;

  insert into public.profiles (
    id, department_id, email_private, full_name, preferred_name, verification_status
  ) values (
    (select auth.uid()), invite.department_id, invite.email, invite.full_name,
    nullif(trim(p_preferred_name), ''), 'pending'
  )
  on conflict (id) do update set
    preferred_name = coalesce(excluded.preferred_name, public.profiles.preferred_name),
    updated_at = now()
  returning * into accepted_profile;

  insert into public.user_roles (profile_id, role_name, granted_by)
  values ((select auth.uid()), 'member', (select auth.uid()))
  on conflict (profile_id, role_name) do nothing;

  foreach consent_name in array array[
    'directory_visibility', 'biography_publication', 'profile_photo_publication',
    'reunion_photo_publication', 'book_publication'
  ] loop
    insert into public.consents (profile_id, consent_type, granted)
    values ((select auth.uid()), consent_name, false)
    on conflict (profile_id, consent_type) do nothing;
  end loop;

  update public.invitations set
    status = 'accepted', accepted_at = now(), accepted_by = (select auth.uid())
  where id = invite.id;

  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), 'invitation.accepted', 'profile', (select auth.uid())::text,
    jsonb_build_object('invitation_id', invite.id, 'verification_status', 'pending'));

  return accepted_profile;
end;
$$;

create or replace function public.create_invitation(
  p_email text,
  p_full_name text,
  p_department_id uuid default null,
  p_expires_days integer default 14
)
returns table (invitation_id uuid, invitation_token text, expires_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  raw_token text;
  new_id uuid;
  expiry timestamptz;
begin
  if not private.is_admin((select auth.uid())) then
    raise exception 'Administrator access required';
  end if;
  if p_email !~* '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then
    raise exception 'A valid email address is required';
  end if;
  if char_length(trim(p_full_name)) not between 2 and 160 then
    raise exception 'A valid full name is required';
  end if;
  if p_expires_days not between 1 and 30 then
    raise exception 'Invitation expiry must be between 1 and 30 days';
  end if;

  raw_token := encode(extensions.gen_random_bytes(24), 'hex');
  expiry := now() + make_interval(days => p_expires_days);

  insert into public.invitations (
    email, full_name, department_id, token_hash, expires_at, created_by
  ) values (
    lower(trim(p_email)), trim(p_full_name), p_department_id,
    encode(extensions.digest(raw_token, 'sha256'), 'hex'), expiry, (select auth.uid())
  ) returning id into new_id;

  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), 'invitation.created', 'invitation', new_id::text,
    jsonb_build_object('department_id', p_department_id, 'expires_at', expiry));

  return query select new_id, raw_token, expiry;
end;
$$;

create or replace function public.review_profile(p_profile_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare previous_status text;
begin
  if not private.is_admin((select auth.uid())) then
    raise exception 'Administrator access required';
  end if;
  if p_status not in ('pending', 'verified', 'rejected', 'suspended') then
    raise exception 'Invalid verification status';
  end if;

  select verification_status into previous_status from public.profiles where id = p_profile_id for update;
  if previous_status is null then raise exception 'Profile not found'; end if;

  update public.profiles set verification_status = p_status where id = p_profile_id;
  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), 'profile.verification_changed', 'profile', p_profile_id::text,
    jsonb_build_object('from', previous_status, 'to', p_status));
end;
$$;

create or replace function public.set_user_role(p_profile_id uuid, p_role text, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_admin((select auth.uid())) then
    raise exception 'Administrator access required';
  end if;
  if p_role not in ('member', 'department_rep', 'committee_lead', 'editor', 'admin', 'finance', 'auditor', 'technical_admin') then
    raise exception 'Invalid role';
  end if;
  if p_role in ('admin', 'technical_admin') and not private.has_role((select auth.uid()), 'technical_admin') then
    raise exception 'Technical administrator access required for privileged roles';
  end if;

  if p_enabled then
    insert into public.user_roles (profile_id, role_name, granted_by)
    values (p_profile_id, p_role, (select auth.uid()))
    on conflict (profile_id, role_name) do nothing;
  else
    delete from public.user_roles where profile_id = p_profile_id and role_name = p_role;
  end if;

  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), case when p_enabled then 'role.granted' else 'role.revoked' end,
    'profile', p_profile_id::text, jsonb_build_object('role', p_role));
end;
$$;

create or replace function public.assign_department_representative(
  p_profile_id uuid,
  p_department_id uuid,
  p_is_india_coordinator boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_admin((select auth.uid())) then
    raise exception 'Administrator access required';
  end if;

  insert into public.department_representatives (
    profile_id, department_id, is_india_coordinator, assigned_by, active
  ) values (
    p_profile_id, p_department_id, p_is_india_coordinator, (select auth.uid()), true
  ) on conflict (department_id, profile_id) do update set
    is_india_coordinator = excluded.is_india_coordinator,
    assigned_by = excluded.assigned_by,
    assigned_at = now(),
    active = true;

  insert into public.user_roles (profile_id, role_name, granted_by)
  values (p_profile_id, 'department_rep', (select auth.uid()))
  on conflict (profile_id, role_name) do nothing;

  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), 'department_representative.assigned', 'profile', p_profile_id::text,
    jsonb_build_object('department_id', p_department_id, 'india_coordinator', p_is_india_coordinator));
end;
$$;

create or replace function public.get_rsvp_summary()
returns table (
  total_profiles bigint,
  responses bigint,
  attending_alumni bigint,
  attending_spouses bigint,
  attending_children bigint,
  undecided bigint,
  not_attending bigint
)
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if not private.is_admin((select auth.uid()))
    and not private.has_role((select auth.uid()), 'department_rep') then
    raise exception 'Organizer access required';
  end if;

  return query
  with scoped_profiles as (
    select p.id
    from public.profiles p
    where p.verification_status in ('pending', 'verified')
      and (
        private.is_admin((select auth.uid()))
        or private.is_department_rep((select auth.uid()), p.department_id)
      )
  )
  select
    count(distinct sp.id),
    count(distinct r.profile_id),
    coalesce(sum(r.alumni_count) filter (where r.attendance_status = 'attending'), 0),
    coalesce(sum(r.spouse_count) filter (where r.attendance_status = 'attending'), 0),
    coalesce(sum(r.child_count) filter (where r.attendance_status = 'attending'), 0),
    count(*) filter (where r.attendance_status = 'undecided'),
    count(*) filter (where r.attendance_status = 'not_attending')
  from scoped_profiles sp
  left join public.rsvps r on r.profile_id = sp.id;
end;
$$;

revoke all on function public.accept_invitation(text, text) from public;
revoke all on function public.create_invitation(text, text, uuid, integer) from public;
revoke all on function public.review_profile(uuid, text) from public;
revoke all on function public.set_user_role(uuid, text, boolean) from public;
revoke all on function public.assign_department_representative(uuid, uuid, boolean) from public;
revoke all on function public.get_rsvp_summary() from public;
grant execute on function public.accept_invitation(text, text) to authenticated;
grant execute on function public.create_invitation(text, text, uuid, integer) to authenticated;
grant execute on function public.review_profile(uuid, text) to authenticated;
grant execute on function public.set_user_role(uuid, text, boolean) to authenticated;
grant execute on function public.assign_department_representative(uuid, uuid, boolean) to authenticated;
grant execute on function public.get_rsvp_summary() to authenticated;

comment on table public.profiles is 'Private alumni profiles created only after authenticated invitation acceptance.';
comment on table public.rsvps is 'Private reunion attendance and family information protected by Row Level Security.';
comment on table public.audit_events is 'Append-only record of sensitive application actions; summaries must not contain private field values.';
