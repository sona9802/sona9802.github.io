begin;

create extension if not exists pgtap with schema extensions;
select plan(4);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('91000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'taskmember@example.test', '', '{}', '{}', now(), now()),
  ('91000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'taskadmin@example.test', '', '{}', '{}', now(), now());

insert into public.profiles (id, email_private, full_name, verification_status) values
  ('91000000-0000-0000-0000-000000000001', 'taskmember@example.test', 'Task Member', 'verified'),
  ('91000000-0000-0000-0000-000000000002', 'taskadmin@example.test', 'Task Admin', 'verified');

insert into public.user_roles (profile_id, role_name) values
  ('91000000-0000-0000-0000-000000000001', 'member'),
  ('91000000-0000-0000-0000-000000000002', 'member'),
  ('91000000-0000-0000-0000-000000000002', 'admin');

insert into public.committee_members (committee_id, profile_id, committee_role, active)
select id, '91000000-0000-0000-0000-000000000001', 'member', true
from public.committees where name = 'Registration & Alumni Outreach';

insert into public.tasks (id, committee_id, owner_profile_id, title, status, created_by, updated_by)
select '92000000-0000-0000-0000-000000000001', id, null, 'RLS regression task', 'ready',
  '91000000-0000-0000-0000-000000000002', '91000000-0000-0000-0000-000000000002'
from public.committees where name = 'Registration & Alumni Outreach';

insert into public.task_assignees (task_id, profile_id, assigned_by)
values ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000002');

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000001","role":"authenticated","email":"taskmember@example.test"}', true);
select lives_ok($$select count(*) from public.tasks$$, 'member task read does not recurse');
select results_eq(
  $$select count(*)::bigint from public.tasks where id = '92000000-0000-0000-0000-000000000001'$$,
  'values (1::bigint)', 'committee member can read the relevant task'
);
select lives_ok($$select count(*) from public.task_assignees$$, 'assignment read does not recurse');

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"91000000-0000-0000-0000-000000000002","role":"authenticated","email":"taskadmin@example.test"}', true);
select lives_ok($$select count(*) from public.tasks$$, 'administrator task read does not recurse');

select * from finish();
rollback;
