begin;

create extension if not exists pgtap with schema extensions;
select plan(24);

select has_table('public', 'departments', 'departments table exists');
select has_table('public', 'invitations', 'invitations table exists');
select has_table('public', 'profiles', 'profiles table exists');
select has_table('public', 'user_roles', 'user roles table exists');
select has_table('public', 'rsvps', 'RSVP table exists');
select has_table('public', 'consents', 'consents table exists');
select has_table('public', 'department_representatives', 'department representatives table exists');
select has_table('public', 'audit_events', 'audit events table exists');

select policies_are(
  'public', 'profiles',
  array['Members update their own profile', 'Profiles have scoped read access'],
  'profiles has only the reviewed Phase 2 policies'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'member1@example.test', '', '{}', '{}', now(), now()),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'member2@example.test', '', '{}', '{}', now(), now()),
  ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'otherdept@example.test', '', '{}', '{}', now(), now()),
  ('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rep@example.test', '', '{}', '{}', now(), now()),
  ('10000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@example.test', '', '{}', '{}', now(), now()),
  ('10000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'suspended@example.test', '', '{}', '{}', now(), now()),
  ('10000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'invited@example.test', '', '{}', '{}', now(), now());

insert into public.departments (id, code, name) values
  ('20000000-0000-0000-0000-000000000001', 'TEST-A', 'Test Department A'),
  ('20000000-0000-0000-0000-000000000002', 'TEST-B', 'Test Department B');

insert into public.profiles (id, department_id, email_private, full_name, verification_status) values
  ('10000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'member1@example.test', 'Member One', 'verified'),
  ('10000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', 'member2@example.test', 'Member Two', 'verified'),
  ('10000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000002', 'otherdept@example.test', 'Other Department', 'verified'),
  ('10000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000001', 'rep@example.test', 'Department Rep', 'verified'),
  ('10000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000002', 'admin@example.test', 'Portal Admin', 'verified'),
  ('10000000-0000-0000-0000-000000000006', '20000000-0000-0000-0000-000000000001', 'suspended@example.test', 'Suspended Member', 'suspended');

insert into public.user_roles (profile_id, role_name) values
  ('10000000-0000-0000-0000-000000000001', 'member'),
  ('10000000-0000-0000-0000-000000000002', 'member'),
  ('10000000-0000-0000-0000-000000000003', 'member'),
  ('10000000-0000-0000-0000-000000000004', 'member'),
  ('10000000-0000-0000-0000-000000000004', 'department_rep'),
  ('10000000-0000-0000-0000-000000000005', 'member'),
  ('10000000-0000-0000-0000-000000000005', 'admin'),
  ('10000000-0000-0000-0000-000000000006', 'member');

insert into public.department_representatives (department_id, profile_id, active)
values ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000004', true);

insert into public.rsvps (profile_id, attendance_status, spouse_count, child_count) values
  ('10000000-0000-0000-0000-000000000001', 'attending', 1, 2),
  ('10000000-0000-0000-0000-000000000002', 'undecided', 0, 0),
  ('10000000-0000-0000-0000-000000000003', 'not_attending', 0, 0);

set local role anon;
select set_config('request.jwt.claims', '{}', true);
select ok(
  not has_table_privilege('anon', 'public.profiles', 'select'),
  'anonymous users cannot read profiles'
);
select results_eq(
  $$select count(*)::bigint from public.departments where code like 'TEST-%'$$,
  'values (2::bigint)',
  'anonymous users can read active departments'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","email":"member1@example.test"}', true);
select results_eq('select count(*)::bigint from public.profiles', 'values (1::bigint)', 'member reads only their own profile');
select results_eq('select count(*)::bigint from public.rsvps', 'values (1::bigint)', 'member reads only their own RSVP');
select results_eq(
  $$with changed as (update public.profiles set city = 'Denied' where id = '10000000-0000-0000-0000-000000000002' returning 1) select count(*)::bigint from changed$$,
  'values (0::bigint)',
  'member cannot update another profile'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated","email":"rep@example.test"}', true);
select results_eq('select count(*)::bigint from public.profiles', 'values (3::bigint)', 'department rep reads only profiles in their department');
select results_eq('select count(*)::bigint from public.rsvps', 'values (2::bigint)', 'department rep reads only RSVPs in their department');

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000006","role":"authenticated","email":"suspended@example.test"}', true);
select results_eq('select count(*)::bigint from public.profiles', 'values (0::bigint)', 'suspended member cannot read even their own profile');

reset role;
insert into public.invitations (id, email, full_name, department_id, token_hash, expires_at)
values (
  '30000000-0000-0000-0000-000000000001', 'invited@example.test', 'Invited Member',
  '20000000-0000-0000-0000-000000000002',
  encode(extensions.digest('test-invitation-token', 'sha256'), 'hex'), now() + interval '1 day'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000007","role":"authenticated","email":"invited@example.test"}', true);
select lives_ok(
  $$select public.accept_invitation('test-invitation-token', 'Invitee')$$,
  'matching authenticated user accepts a valid invitation'
);
select results_eq(
  $$select count(*)::bigint from public.profiles where id = '10000000-0000-0000-0000-000000000007'$$,
  'values (1::bigint)', 'invitation acceptance creates a profile'
);
select results_eq(
  $$select count(*)::bigint from public.consents where profile_id = '10000000-0000-0000-0000-000000000007' and not granted$$,
  'values (5::bigint)', 'all publication consents default to off'
);

reset role;
select results_eq(
  $$select count(*)::bigint from public.audit_events where actor_id = '10000000-0000-0000-0000-000000000007' and action = 'invitation.accepted'$$,
  'values (1::bigint)', 'invitation acceptance creates an audit event'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated","email":"admin@example.test"}', true);
select results_eq('select total_profiles from public.get_rsvp_summary()', 'values (6::bigint)', 'administrator summary counts active profiles');
select results_eq('select attending_children from public.get_rsvp_summary()', 'values (2::bigint)', 'administrator summary reconciles child headcount');
select lives_ok(
  $$select public.review_profile('10000000-0000-0000-0000-000000000002', 'verified')$$,
  'administrator can review a profile through the audited function'
);

select * from finish();
rollback;
