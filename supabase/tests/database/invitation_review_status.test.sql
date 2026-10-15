begin;

create extension if not exists pgtap with schema extensions;
select plan(5);

select has_function('public', 'invitation_review_queue', 'invitation review queue function exists');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data, email_confirmed_at, last_sign_in_at, created_at, updated_at
) values
  ('97000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'review-admin@example.test', '', '{}', '{}', now(), now(), now(), now()),
  ('97000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'signed-in-member@example.test', '', '{}', '{}', now(), now(), now(), now()),
  ('97000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'invited-member@example.test', '', '{}', '{}', null, null, now(), now());

insert into public.profiles (id, email_private, full_name, verification_status) values
  ('97000000-0000-0000-0000-000000000001', 'review-admin@example.test', 'Review Admin', 'verified'),
  ('97000000-0000-0000-0000-000000000002', 'signed-in-member@example.test', 'Signed In Member', 'invited'),
  ('97000000-0000-0000-0000-000000000003', 'invited-member@example.test', 'Invited Member', 'invited');

insert into public.user_roles (profile_id, role_name) values
  ('97000000-0000-0000-0000-000000000001', 'admin'),
  ('97000000-0000-0000-0000-000000000002', 'member'),
  ('97000000-0000-0000-0000-000000000003', 'member');

insert into public.invitations (email, full_name, token_hash, expires_at, created_by) values
  ('signed-in-member@example.test', 'Signed In Member', repeat('b', 64), now() + interval '14 days', '97000000-0000-0000-0000-000000000001'),
  ('invited-member@example.test', 'Invited Member', repeat('c', 64), now() + interval '14 days', '97000000-0000-0000-0000-000000000001');

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"97000000-0000-0000-0000-000000000001","role":"authenticated","email":"review-admin@example.test"}', true);

select results_eq(
  $$select display_status from public.invitation_review_queue() where email = 'signed-in-member@example.test'$$,
  $$values ('signed_in_activation_pending'::text)$$,
  'signed-in invited member is shown as activation pending'
);
select results_eq(
  $$select display_status from public.invitation_review_queue() where email = 'invited-member@example.test'$$,
  $$values ('invited'::text)$$,
  'member who has not signed in remains invited'
);
select results_eq(
  $$select count(*)::bigint from public.invitation_review_queue()$$,
  $$values (3::bigint)$$,
  'administrator can see the review queue'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"97000000-0000-0000-0000-000000000002","role":"authenticated","email":"signed-in-member@example.test"}', true);
select results_eq(
  $$select count(*)::bigint from public.invitation_review_queue()$$,
  $$values (0::bigint)$$,
  'ordinary members cannot see the invitation review queue'
);

select * from finish();
rollback;
