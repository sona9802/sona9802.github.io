-- One-time fallback activation for the confirmed first-administrator account.
--
-- Production has a confirmed auth user for sct9802@gmail.com, but browser-based
-- invitation activation was unreliable during the pilot. This migration performs
-- the same profile, default-consent, invitation, role, and audit writes as the
-- normal acceptance flow. It is a no-op in fresh/local environments where that
-- auth user does not exist.
do $$
declare
  administrator_id uuid;
  administrator_confirmed_at timestamptz;
  bootstrap_invitation public.invitations;
  consent_name text;
begin
  select id, email_confirmed_at
  into administrator_id, administrator_confirmed_at
  from auth.users
  where lower(email) = 'sct9802@gmail.com';

  if administrator_id is null then
    raise notice 'Confirmed first-administrator auth user is absent; skipping production bootstrap';
    return;
  end if;

  if administrator_confirmed_at is null then
    raise exception 'First-administrator email ownership has not been confirmed';
  end if;

  if exists (
    select 1
    from public.user_roles
    where profile_id = administrator_id
      and role_name = 'technical_admin'
  ) then
    raise notice 'First administrator is already assigned; no changes required';
    return;
  end if;

  if exists (select 1 from public.profiles where id = administrator_id) then
    raise exception 'First-administrator profile already exists without the required role';
  end if;

  select *
  into bootstrap_invitation
  from public.invitations
  where lower(email::text) = 'sct9802@gmail.com'
    and status = 'pending'
    and expires_at > now()
    and bootstrap_technical_admin
  for update;

  if bootstrap_invitation.id is null then
    raise exception 'Valid pending first-administrator invitation was not found';
  end if;

  insert into public.profiles (
    id,
    department_id,
    email_private,
    full_name,
    verification_status
  ) values (
    administrator_id,
    bootstrap_invitation.department_id,
    bootstrap_invitation.email,
    bootstrap_invitation.full_name,
    'pending'
  );

  insert into public.user_roles (profile_id, role_name, granted_by)
  values (administrator_id, 'member', administrator_id);

  foreach consent_name in array array[
    'directory_visibility',
    'biography_publication',
    'profile_photo_publication',
    'reunion_photo_publication',
    'book_publication'
  ] loop
    insert into public.consents (profile_id, consent_type, granted)
    values (administrator_id, consent_name, false);
  end loop;

  -- The existing bootstrap trigger grants technical_admin, verifies the profile,
  -- records role.bootstrap_granted, and clears the bootstrap marker.
  update public.invitations
  set
    status = 'accepted',
    accepted_at = now(),
    accepted_by = administrator_id,
    updated_at = now()
  where id = bootstrap_invitation.id;

  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values (
    administrator_id,
    'invitation.accepted_by_operator',
    'profile',
    administrator_id::text,
    jsonb_build_object(
      'invitation_id', bootstrap_invitation.id,
      'reason', 'first-administrator pilot fallback',
      'email_ownership_confirmed', true
    )
  );

  if not exists (
    select 1
    from public.user_roles
    where profile_id = administrator_id
      and role_name = 'technical_admin'
  ) then
    raise exception 'First-administrator role assignment did not complete';
  end if;
end;
$$;
