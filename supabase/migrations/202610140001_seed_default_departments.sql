-- Seed the default reunion departments used by invitations, profiles,
-- representatives, coverage, and outreach. Upserting by code preserves the
-- identity of any existing row (and therefore all foreign-key references).
insert into public.departments (code, name, active)
values
  ('IT', 'Information Technology', true),
  ('CSE', 'Computer Science and Engineering', true),
  ('EEE', 'Electrical and Electronics Engineering', true),
  ('MECH', 'Mechanical Engineering', true),
  ('ECE', 'Electronics and Communication Engineering', true),
  ('STAFF', 'Staff', true)
on conflict (code) do update
set
  name = excluded.name,
  active = true,
  updated_at = now();

