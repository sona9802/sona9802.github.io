-- Correct the first-administrator invitation hash after the out-of-band token
-- delivered to the organizer was found not to match the bootstrap record.
-- The readable invitation token remains outside source control.
do $$
declare
  updated_count integer;
begin
  update public.invitations
  set
    token_hash = 'c7f812610c25ad3d6d4a53fc7578b04fa315b33289ccce74fa958b770642fc76',
    expires_at = now() + interval '14 days',
    updated_at = now()
  where lower(email::text) = 'sct9802@gmail.com'
    and status = 'pending'
    and bootstrap_technical_admin;

  get diagnostics updated_count = row_count;
  if updated_count <> 1 then
    raise exception 'Pending first-administrator invitation was not found';
  end if;
end;
$$;
