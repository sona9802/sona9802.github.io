-- Local synthetic data only. Never place real alumni information in this file.
insert into public.app_settings (key, value, is_public)
values ('environment_label', '{"label":"Local development"}', true)
on conflict (key) do update set value = excluded.value;

-- Reference data only. Test users are created inside transactional pgTAP tests.
insert into public.departments (code, name)
values
  ('CSE', 'Computer Science and Engineering'),
  ('ECE', 'Electronics and Communication Engineering'),
  ('EEE', 'Electrical and Electronics Engineering'),
  ('MECH', 'Mechanical Engineering'),
  ('CIVIL', 'Civil Engineering'),
  ('IT', 'Information Technology')
on conflict (code) do update set name = excluded.name, active = true;
