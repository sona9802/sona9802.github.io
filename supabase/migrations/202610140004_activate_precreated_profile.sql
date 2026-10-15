-- Let authenticated invitees with a pre-created `invited` profile complete
-- the same one-time invitation activation as invitees without a profile.

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
    verification_status = case
      when public.profiles.verification_status = 'invited' then 'pending'
      else public.profiles.verification_status
    end,
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
    jsonb_build_object('invitation_id', invite.id, 'verification_status', accepted_profile.verification_status));

  return accepted_profile;
end;
$$;
