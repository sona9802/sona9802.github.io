begin;

create extension if not exists pgtap with schema extensions;
select plan(7);

select has_function('public', 'committee_workspace_members', 'committee roster workspace function exists');
select has_function('public', 'committee_workspace_tasks', 'committee task workspace function exists');

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('93000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'workspace-viewer@example.test', '', '{}', '{}', now(), now()),
  ('93000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'workspace-lead@example.test', '', '{}', '{}', now(), now());

insert into public.profiles (id, email_private, full_name, preferred_name, verification_status) values
  ('93000000-0000-0000-0000-000000000001', 'workspace-viewer@example.test', 'Workspace Viewer', null, 'verified'),
  ('93000000-0000-0000-0000-000000000002', 'workspace-lead@example.test', 'Workspace Lead Legal Name', 'Workspace Lead', 'verified');

insert into public.user_roles (profile_id, role_name) values
  ('93000000-0000-0000-0000-000000000001', 'member'),
  ('93000000-0000-0000-0000-000000000002', 'member');

insert into public.committee_members (committee_id, profile_id, committee_role, active)
select id, '93000000-0000-0000-0000-000000000002', 'lead', true
from public.committees where name = 'Registration & Alumni Outreach';

insert into public.tasks (id, committee_id, owner_profile_id, title, description, status, created_by, updated_by)
select '94000000-0000-0000-0000-000000000001', id, '93000000-0000-0000-0000-000000000002',
  'Workspace visible task', 'Safe summary', 'ready',
  '93000000-0000-0000-0000-000000000002', '93000000-0000-0000-0000-000000000002'
from public.committees where name = 'Registration & Alumni Outreach';

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"93000000-0000-0000-0000-000000000001","role":"authenticated","email":"workspace-viewer@example.test"}', true);

select lives_ok($$select * from public.committee_workspace_members()$$, 'active member can load committee rosters');
select lives_ok($$select * from public.committee_workspace_tasks()$$, 'active member can load committee tasks');
select results_eq(
  $$select display_name from public.committee_workspace_members() where profile_id = '93000000-0000-0000-0000-000000000002'$$,
  $$values ('Workspace Lead'::text)$$,
  'roster prefers the member preferred name'
);
select results_eq(
  $$select title from public.committee_workspace_tasks() where id = '94000000-0000-0000-0000-000000000001'$$,
  $$values ('Workspace visible task'::text)$$,
  'member can see a task from a committee they have not joined'
);
select results_eq(
  $$select owner_display_name from public.committee_workspace_tasks() where id = '94000000-0000-0000-0000-000000000001'$$,
  $$values ('Workspace Lead'::text)$$,
  'task feed includes only the privacy-safe owner display name'
);

select * from finish();
rollback;
