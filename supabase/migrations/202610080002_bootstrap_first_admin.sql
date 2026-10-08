-- One-time bootstrap for the first technical administrator.
-- The readable token is deliberately kept outside source control; only its hash is stored here.
alter table public.invitations
  add column bootstrap_technical_admin boolean not null default false;

create or replace function private.promote_bootstrap_administrator()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'accepted'
    and old.status <> 'accepted'
    and new.bootstrap_technical_admin
    and not exists (
      select 1 from public.user_roles where role_name = 'technical_admin'
    ) then
    insert into public.user_roles (profile_id, role_name, granted_by)
    values (new.accepted_by, 'technical_admin', new.accepted_by)
    on conflict (profile_id, role_name) do nothing;

    update public.profiles
    set verification_status = 'verified'
    where id = new.accepted_by;

    insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
    values (
      new.accepted_by,
      'role.bootstrap_granted',
      'profile',
      new.accepted_by::text,
      jsonb_build_object('role', 'technical_admin', 'invitation_id', new.id)
    );

    update public.invitations
    set bootstrap_technical_admin = false
    where id = new.id;
  end if;

  return new;
end;
$$;

create trigger invitations_bootstrap_first_administrator
after update of status on public.invitations
for each row execute function private.promote_bootstrap_administrator();

insert into public.invitations (
  email,
  full_name,
  token_hash,
  expires_at,
  bootstrap_technical_admin
) values (
  'sct9802@gmail.com',
  'SCT 98–02 Administrator',
  '3f77bb13884d89ab01b86ba124f265d8fe41010116f8de0dd11f5101e3b7ac88',
  now() + interval '14 days',
  true
)
on conflict (lower(email::text)) where status = 'pending'
do update set
  full_name = excluded.full_name,
  token_hash = excluded.token_hash,
  expires_at = excluded.expires_at,
  bootstrap_technical_admin = true,
  updated_at = now();

comment on column public.invitations.bootstrap_technical_admin is
  'One-time operator-created bootstrap marker. Cleared automatically when the first technical administrator accepts.';
