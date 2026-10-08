-- Phase 0 foundation: schema conventions and non-sensitive configuration.
create extension if not exists pgcrypto with schema extensions;

create table public.app_settings (
  key text primary key,
  value jsonb not null,
  is_public boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.app_settings enable row level security;

create policy "Public settings are readable"
  on public.app_settings
  for select
  using (is_public = true);

insert into public.app_settings (key, value, is_public)
values
  ('event_dates', '{"start":"2027-07-16","end":"2027-07-18"}', true),
  ('event_venue', '{"name":"Sona College of Technology","city":"Salem","state":"Tamil Nadu"}', true);

comment on table public.app_settings is
  'Non-sensitive portal configuration. Private member data is introduced only after Phase 2 security gates pass.';
