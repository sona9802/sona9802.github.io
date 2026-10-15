begin;

create extension if not exists pgtap with schema extensions;
select plan(5);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data, email_confirmed_at, last_sign_in_at, created_at, updated_at
) values (
  '98000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'precreated-invitee@example.test', '', '{}', '{}', now(), now(), now(), now()
);

insert into public.profiles (id, email_private, full_name, verification_status)
values ('98000000-0000-0000-0000-000000000001', 'precreated-invitee@example.test', 'Precreated Invitee', 'invited');

insert into public.invitations (id, email, full_name, token_hash, expires_at)
values (
  '99000000-0000-0000-0000-000000000001', 'precreated-invitee@example.test', 'Precreated Invitee',
  encode(extensions.digest('known-activation-token', 'sha256'), 'hex'), now() + interval '14 days'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"98000000-0000-0000-0000-000000000001","role":"authenticated","email":"precreated-invitee@example.test"}', true);

select lives_ok(
  $$select public.accept_invitation('known-activation-token', 'Invitee')$$,
  'invitee with a pre-created profile can activate'
);

reset role;

select results_eq(
  $$select verification_status from public.profiles where id = '98000000-0000-0000-0000-000000000001'$$,
  $$values ('pending'::text)$$,
  'pre-created profile advances to pending organizer review'
);
select results_eq(
  $$select status from public.invitations where id = '99000000-0000-0000-0000-000000000001'$$,
  $$values ('accepted'::text)$$,
  'invitation is marked accepted'
);
select results_eq(
  $$select count(*)::bigint from public.consents where profile_id = '98000000-0000-0000-0000-000000000001'$$,
  $$values (5::bigint)$$,
  'default consent decisions are created'
);
select results_eq(
  $$select count(*)::bigint from public.audit_events where actor_id = '98000000-0000-0000-0000-000000000001' and action = 'invitation.accepted'$$,
  $$values (1::bigint)$$,
  'activation is recorded in the audit log'
);

select * from finish();
rollback;
