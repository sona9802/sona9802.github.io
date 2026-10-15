-- Administrator-only invitation lifecycle view. Authentication, invitation
-- activation, and organizer verification are separate stages, so the portal
-- must not describe a member who has signed in as merely "invited".

create or replace function public.invitation_review_queue()
returns table (
  profile_id uuid,
  email text,
  full_name text,
  profile_status text,
  invitation_status text,
  invitation_expires_at timestamptz,
  email_confirmed_at timestamptz,
  last_sign_in_at timestamptz,
  display_status text
)
language sql stable security definer set search_path = '' as $$
  select
    profile.id,
    profile.email_private::text,
    profile.full_name,
    profile.verification_status,
    invitation.status,
    invitation.expires_at,
    account.email_confirmed_at,
    account.last_sign_in_at,
    case
      when profile.verification_status = 'verified' then 'verified'
      when profile.verification_status = 'rejected' then 'rejected'
      when profile.verification_status = 'suspended' then 'suspended'
      when profile.verification_status = 'pending' then 'awaiting_verification'
      when account.last_sign_in_at is not null then 'signed_in_activation_pending'
      when invitation.status = 'pending' and invitation.expires_at < now() then 'invitation_expired'
      else 'invited'
    end
  from public.profiles profile
  join auth.users account on account.id = profile.id
  left join lateral (
    select candidate.status, candidate.expires_at
    from public.invitations candidate
    where lower(candidate.email::text) = lower(profile.email_private::text)
    order by candidate.created_at desc
    limit 1
  ) invitation on true
  where private.is_admin((select auth.uid()))
  order by account.last_sign_in_at desc nulls last, profile.full_name;
$$;

revoke all on function public.invitation_review_queue() from public;
grant execute on function public.invitation_review_queue() to authenticated;

comment on function public.invitation_review_queue() is
  'Returns administrator-only invitation, authentication, and profile-review lifecycle statuses.';
