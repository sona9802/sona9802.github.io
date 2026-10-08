-- Local synthetic data only. Never place real alumni information in this file.
insert into public.app_settings (key, value, is_public)
values ('environment_label', '{"label":"Local development"}', true)
on conflict (key) do update set value = excluded.value;
