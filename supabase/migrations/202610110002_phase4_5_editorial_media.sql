-- Phases 4 and 5: biographies, private media, editorial workflow,
-- consent-aware moderation, public-gallery approval, and audited book exports.

create table public.biographies (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null unique references public.profiles(id) on delete cascade,
  version integer not null default 1 check (version > 0),
  original_text text not null default '' check (char_length(original_text) <= 5000),
  submitted_text text,
  edited_text text,
  editor_note text,
  editorial_status text not null default 'draft' check (
    editorial_status in ('draft', 'submitted', 'revision_requested', 'edited', 'member_approved', 'publication_approved', 'withdrawn')
  ),
  submitted_at timestamptz,
  edited_at timestamptz,
  member_approved_at timestamptz,
  publication_approved_at timestamptz,
  withdrawn_at timestamptz,
  editor_id uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.media_assets (
  id uuid primary key default gen_random_uuid(),
  uploader_profile_id uuid not null references public.profiles(id) on delete cascade,
  storage_bucket text not null check (storage_bucket in ('profile-photos-private', 'reunion-photos-private', 'book-assets-approved', 'public-gallery')),
  storage_path text not null unique,
  media_type text not null check (media_type in ('profile_photo', 'memory_photo')),
  category text not null default 'current' check (category in ('college_era', 'current', 'reunion', 'family', 'other')),
  caption text check (caption is null or char_length(caption) <= 500),
  approximate_date date,
  contributor_name text check (contributor_name is null or char_length(contributor_name) <= 160),
  mime_type text not null check (mime_type in ('image/jpeg', 'image/png', 'image/webp')),
  file_size_bytes bigint not null check (file_size_bytes > 0 and file_size_bytes <= 2097152),
  checksum text,
  moderation_status text not null default 'private' check (
    moderation_status in ('private', 'submitted', 'revision_requested', 'approved', 'rejected', 'withdrawn')
  ),
  reviewer_note text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  book_approved boolean not null default false,
  public_gallery_approved boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index one_active_profile_photo_per_member on public.media_assets (uploader_profile_id)
where media_type = 'profile_photo' and moderation_status <> 'withdrawn';

create table public.content_exports (
  id uuid primary key default gen_random_uuid(),
  export_type text not null check (export_type in ('book_manifest', 'operations_summary', 'personal_data')),
  payload jsonb not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  downloaded_at timestamptz,
  revoked_at timestamptz
);

create index biographies_status_idx on public.biographies (editorial_status, updated_at);
create index media_assets_review_idx on public.media_assets (moderation_status, media_type, created_at);
create index content_exports_expiry_idx on public.content_exports (expires_at) where revoked_at is null;

create trigger biographies_touch_updated_at before update on public.biographies
for each row execute function private.touch_updated_at();
create trigger media_assets_touch_updated_at before update on public.media_assets
for each row execute function private.touch_updated_at();

create or replace function private.is_editor(target_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_admin(target_user) or private.has_role(target_user, 'editor');
$$;

create or replace function private.has_consent(target_profile uuid, target_type text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.consents
    where profile_id = target_profile and consent_type = target_type and granted
  );
$$;

revoke all on function private.is_editor(uuid) from public;
revoke all on function private.has_consent(uuid, text) from public;
grant execute on function private.is_editor(uuid) to authenticated;
grant execute on function private.has_consent(uuid, text) to authenticated;

create or replace function public.save_biography_draft(p_text text)
returns public.biographies language plpgsql security definer set search_path = '' as $$
declare result public.biographies; current_status text;
begin
  if not private.is_active_user((select auth.uid())) then raise exception 'Active member profile required'; end if;
  if char_length(trim(coalesce(p_text, ''))) > 5000 then raise exception 'Biography is too long'; end if;
  select editorial_status into current_status from public.biographies where profile_id = (select auth.uid());
  if current_status in ('edited', 'member_approved', 'publication_approved') then
    raise exception 'Use revision request workflow after editorial review';
  end if;
  insert into public.biographies (profile_id, original_text, editorial_status)
  values ((select auth.uid()), trim(coalesce(p_text, '')), 'draft')
  on conflict (profile_id) do update set original_text = excluded.original_text,
    editorial_status = case when public.biographies.editorial_status = 'withdrawn' then 'draft' else public.biographies.editorial_status end,
    version = public.biographies.version + 1, withdrawn_at = null, updated_at = now()
  returning * into result;
  return result;
end;
$$;

create or replace function public.submit_biography()
returns public.biographies language plpgsql security definer set search_path = '' as $$
declare result public.biographies;
begin
  update public.biographies set editorial_status = 'submitted', submitted_text = original_text,
    submitted_at = now(), member_approved_at = null, publication_approved_at = null
  where profile_id = (select auth.uid())
    and editorial_status in ('draft', 'revision_requested')
    and char_length(trim(original_text)) >= 20
  returning * into result;
  if result.id is null then raise exception 'Save at least 20 characters before submitting'; end if;
  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), 'biography.submitted', 'biography', result.id::text,
    jsonb_build_object('version', result.version));
  return result;
end;
$$;

create or replace function public.review_biography(
  p_biography_id uuid, p_status text, p_edited_text text default null, p_editor_note text default null
)
returns public.biographies language plpgsql security definer set search_path = '' as $$
declare result public.biographies; target public.biographies;
begin
  if not private.is_editor((select auth.uid())) then raise exception 'Editor access required'; end if;
  if p_status not in ('revision_requested', 'edited', 'publication_approved') then raise exception 'Invalid editorial decision'; end if;
  select * into target from public.biographies where id = p_biography_id for update;
  if target.id is null then raise exception 'Biography not found'; end if;
  if p_status = 'edited' and char_length(trim(coalesce(p_edited_text, ''))) < 20 then raise exception 'Edited biography is required'; end if;
  if p_status = 'publication_approved' and (
    target.editorial_status <> 'member_approved'
    or not private.has_consent(target.profile_id, 'biography_publication')
    or not private.has_consent(target.profile_id, 'book_publication')
  ) then raise exception 'Member approval and current biography/book consent are required'; end if;
  update public.biographies set editorial_status = p_status,
    edited_text = case when p_status = 'edited' then trim(p_edited_text) else edited_text end,
    editor_note = nullif(trim(p_editor_note), ''), editor_id = (select auth.uid()),
    edited_at = case when p_status = 'edited' then now() else edited_at end,
    publication_approved_at = case when p_status = 'publication_approved' then now() else null end
  where id = p_biography_id returning * into result;
  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), 'biography.reviewed', 'biography', p_biography_id::text,
    jsonb_build_object('from', target.editorial_status, 'to', p_status));
  return result;
end;
$$;

create or replace function public.approve_edited_biography()
returns public.biographies language plpgsql security definer set search_path = '' as $$
declare result public.biographies;
begin
  update public.biographies set editorial_status = 'member_approved', member_approved_at = now()
  where profile_id = (select auth.uid()) and editorial_status = 'edited' and edited_text is not null
  returning * into result;
  if result.id is null then raise exception 'No edited biography is awaiting approval'; end if;
  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), 'biography.member_approved', 'biography', result.id::text, '{}'::jsonb);
  return result;
end;
$$;

create or replace function public.withdraw_biography()
returns void language plpgsql security definer set search_path = '' as $$
declare target_id uuid;
begin
  update public.biographies set editorial_status = 'withdrawn', withdrawn_at = now(), publication_approved_at = null
  where profile_id = (select auth.uid()) returning id into target_id;
  if target_id is null then raise exception 'Biography not found'; end if;
  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), 'biography.withdrawn', 'biography', target_id::text, '{}'::jsonb);
end;
$$;

create or replace function public.register_media_asset(
  p_asset_id uuid, p_bucket text, p_path text, p_media_type text, p_category text,
  p_caption text, p_mime_type text, p_file_size_bytes bigint, p_checksum text default null
)
returns public.media_assets language plpgsql security definer set search_path = '' as $$
declare result public.media_assets; max_size bigint;
begin
  if not private.is_active_user((select auth.uid())) then raise exception 'Active member profile required'; end if;
  if p_bucket not in ('profile-photos-private', 'reunion-photos-private') then raise exception 'Private upload bucket required'; end if;
  if p_media_type not in ('profile_photo', 'memory_photo') then raise exception 'Invalid media type'; end if;
  if (p_media_type = 'profile_photo' and p_bucket <> 'profile-photos-private')
    or (p_media_type = 'memory_photo' and p_bucket <> 'reunion-photos-private') then raise exception 'Media type and bucket do not match'; end if;
  if p_mime_type not in ('image/jpeg', 'image/png', 'image/webp') then raise exception 'Unsupported image format'; end if;
  max_size := case when p_media_type = 'profile_photo' then 1048576 else 2097152 end;
  if p_file_size_bytes <= 0 or p_file_size_bytes > max_size then raise exception 'Image exceeds the upload limit'; end if;
  if split_part(p_path, '/', 1) <> (select auth.uid())::text then raise exception 'Invalid storage path'; end if;
  if not exists (select 1 from storage.objects where bucket_id = p_bucket and name = p_path) then raise exception 'Uploaded object was not found'; end if;
  insert into public.media_assets (id, uploader_profile_id, storage_bucket, storage_path, media_type,
    category, caption, mime_type, file_size_bytes, checksum)
  values (p_asset_id, (select auth.uid()), p_bucket, p_path, p_media_type, p_category,
    nullif(trim(p_caption), ''), p_mime_type, p_file_size_bytes, nullif(trim(p_checksum), ''))
  returning * into result;
  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), 'media.uploaded', 'media_asset', result.id::text,
    jsonb_build_object('media_type', p_media_type, 'bucket', p_bucket));
  return result;
end;
$$;

create or replace function public.submit_media_asset(p_asset_id uuid)
returns public.media_assets language plpgsql security definer set search_path = '' as $$
declare result public.media_assets;
begin
  update public.media_assets set moderation_status = 'submitted'
  where id = p_asset_id and uploader_profile_id = (select auth.uid())
    and moderation_status in ('private', 'revision_requested', 'rejected')
  returning * into result;
  if result.id is null then raise exception 'Media asset is not available for submission'; end if;
  return result;
end;
$$;

create or replace function public.review_media_asset(
  p_asset_id uuid, p_status text, p_reviewer_note text default null,
  p_book_approved boolean default false, p_public_gallery_approved boolean default false
)
returns public.media_assets language plpgsql security definer set search_path = '' as $$
declare target public.media_assets; result public.media_assets; consent_type text;
begin
  if not private.is_editor((select auth.uid())) then raise exception 'Editor access required'; end if;
  if p_status not in ('revision_requested', 'approved', 'rejected') then raise exception 'Invalid moderation decision'; end if;
  select * into target from public.media_assets where id = p_asset_id for update;
  if target.id is null then raise exception 'Media asset not found'; end if;
  consent_type := case when target.media_type = 'profile_photo' then 'profile_photo_publication' else 'reunion_photo_publication' end;
  if p_status = 'approved' and not private.has_consent(target.uploader_profile_id, consent_type) then
    raise exception 'Current photo publication consent is required';
  end if;
  if p_book_approved and not private.has_consent(target.uploader_profile_id, 'book_publication') then
    raise exception 'Current book publication consent is required';
  end if;
  update public.media_assets set moderation_status = p_status, reviewer_note = nullif(trim(p_reviewer_note), ''),
    reviewed_by = (select auth.uid()), reviewed_at = now(),
    book_approved = p_status = 'approved' and p_book_approved,
    public_gallery_approved = p_status = 'approved' and p_public_gallery_approved
  where id = p_asset_id returning * into result;
  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), 'media.reviewed', 'media_asset', p_asset_id::text,
    jsonb_build_object('from', target.moderation_status, 'to', p_status,
      'book_approved', result.book_approved, 'public_gallery_approved', result.public_gallery_approved));
  return result;
end;
$$;

create or replace function public.delete_media_asset(p_asset_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare target public.media_assets;
begin
  select * into target from public.media_assets where id = p_asset_id for update;
  if target.id is null then raise exception 'Media asset not found'; end if;
  if target.uploader_profile_id <> (select auth.uid()) and not private.is_admin((select auth.uid())) then raise exception 'Not authorized'; end if;
  delete from storage.objects where bucket_id = target.storage_bucket and name = target.storage_path;
  delete from public.media_assets where id = p_asset_id;
  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), 'media.deleted', 'media_asset', p_asset_id::text,
    jsonb_build_object('media_type', target.media_type));
end;
$$;

create or replace function public.generate_book_export()
returns table (export_id uuid, export_payload jsonb, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare payload jsonb; new_id uuid; expiry timestamptz;
begin
  if not private.is_editor((select auth.uid())) then raise exception 'Editor access required'; end if;
  payload := jsonb_build_object(
    'generated_at', now(),
    'biographies', coalesce((select jsonb_agg(jsonb_build_object(
      'profile_id', p.id, 'display_name', coalesce(p.preferred_name, p.full_name),
      'department', d.code, 'text', coalesce(b.edited_text, b.submitted_text), 'version', b.version
    ) order by d.code, coalesce(p.preferred_name, p.full_name))
      from public.biographies b join public.profiles p on p.id = b.profile_id
      left join public.departments d on d.id = p.department_id
      where b.editorial_status = 'publication_approved'
        and private.has_consent(p.id, 'biography_publication')
        and private.has_consent(p.id, 'book_publication')), '[]'::jsonb),
    'media', coalesce((select jsonb_agg(jsonb_build_object(
      'asset_id', m.id, 'profile_id', p.id, 'display_name', coalesce(p.preferred_name, p.full_name),
      'department', d.code, 'storage_bucket', m.storage_bucket, 'storage_path', m.storage_path,
      'category', m.category, 'caption', m.caption, 'contributor', m.contributor_name, 'checksum', m.checksum
    ) order by d.code, coalesce(p.preferred_name, p.full_name), m.created_at)
      from public.media_assets m join public.profiles p on p.id = m.uploader_profile_id
      left join public.departments d on d.id = p.department_id
      where m.moderation_status = 'approved' and m.book_approved
        and private.has_consent(p.id, 'book_publication')
        and private.has_consent(p.id, case when m.media_type = 'profile_photo' then 'profile_photo_publication' else 'reunion_photo_publication' end)), '[]'::jsonb)
  );
  expiry := now() + interval '1 hour';
  insert into public.content_exports (export_type, payload, created_by, expires_at)
  values ('book_manifest', payload, (select auth.uid()), expiry) returning id into new_id;
  insert into public.audit_events (actor_id, action, entity_type, entity_id, summary)
  values ((select auth.uid()), 'export.generated', 'content_export', new_id::text,
    jsonb_build_object('export_type', 'book_manifest', 'expires_at', expiry));
  return query select new_id, payload, expiry;
end;
$$;

create or replace function public.public_gallery_manifest()
returns table (asset_id uuid, caption text, category text, storage_bucket text, storage_path text)
language sql stable security definer set search_path = '' as $$
  select m.id, m.caption, m.category, m.storage_bucket, m.storage_path
  from public.media_assets m
  where m.moderation_status = 'approved' and m.public_gallery_approved
    and m.storage_bucket = 'public-gallery'
    and private.has_consent(m.uploader_profile_id,
      case when m.media_type = 'profile_photo' then 'profile_photo_publication' else 'reunion_photo_publication' end)
  order by m.created_at desc;
$$;

create or replace function public.editor_profile_labels()
returns table (profile_id uuid, display_name text, department_code text)
language sql stable security definer set search_path = '' as $$
  select p.id, coalesce(p.preferred_name, p.full_name), d.code
  from public.profiles p left join public.departments d on d.id = p.department_id
  where private.is_editor((select auth.uid()))
    and p.verification_status in ('pending', 'verified')
  order by d.code nulls last, coalesce(p.preferred_name, p.full_name);
$$;

alter table public.biographies enable row level security;
alter table public.media_assets enable row level security;
alter table public.content_exports enable row level security;

create policy "Members read own biography and editors read review queue" on public.biographies for select to authenticated
using (profile_id = (select auth.uid()) or private.is_editor((select auth.uid())));
create policy "Members insert own biography" on public.biographies for insert to authenticated
with check (profile_id = (select auth.uid()));
create policy "Members update own biography" on public.biographies for update to authenticated
using (profile_id = (select auth.uid())) with check (profile_id = (select auth.uid()));

create policy "Members read own media and editors read submissions" on public.media_assets for select to authenticated
using (uploader_profile_id = (select auth.uid()) or private.is_editor((select auth.uid())));
create policy "Members insert own media metadata" on public.media_assets for insert to authenticated
with check (uploader_profile_id = (select auth.uid()));
create policy "Members update own media description" on public.media_assets for update to authenticated
using (uploader_profile_id = (select auth.uid())) with check (uploader_profile_id = (select auth.uid()));
create policy "Editors read generated exports" on public.content_exports for select to authenticated
using (created_by = (select auth.uid()) or private.is_admin((select auth.uid())));

grant select on public.biographies, public.media_assets, public.content_exports to authenticated;
grant insert on public.biographies, public.media_assets to authenticated;
grant update (original_text) on public.biographies to authenticated;
grant update (category, caption, approximate_date, contributor_name) on public.media_assets to authenticated;
grant execute on function public.save_biography_draft(text) to authenticated;
grant execute on function public.submit_biography() to authenticated;
grant execute on function public.review_biography(uuid, text, text, text) to authenticated;
grant execute on function public.approve_edited_biography() to authenticated;
grant execute on function public.withdraw_biography() to authenticated;
grant execute on function public.register_media_asset(uuid, text, text, text, text, text, text, bigint, text) to authenticated;
grant execute on function public.submit_media_asset(uuid) to authenticated;
grant execute on function public.review_media_asset(uuid, text, text, boolean, boolean) to authenticated;
grant execute on function public.delete_media_asset(uuid) to authenticated;
grant execute on function public.generate_book_export() to authenticated;
grant execute on function public.public_gallery_manifest() to anon, authenticated;
grant execute on function public.editor_profile_labels() to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('profile-photos-private', 'profile-photos-private', false, 1048576, array['image/jpeg', 'image/png', 'image/webp']),
  ('reunion-photos-private', 'reunion-photos-private', false, 2097152, array['image/jpeg', 'image/png', 'image/webp']),
  ('book-assets-approved', 'book-assets-approved', false, 2097152, array['image/jpeg', 'image/png', 'image/webp']),
  ('public-gallery', 'public-gallery', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy "Members upload private images to own folder" on storage.objects for insert to authenticated
with check (
  bucket_id in ('profile-photos-private', 'reunion-photos-private')
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and private.is_active_user((select auth.uid()))
);
create policy "Members and editors read permitted private images" on storage.objects for select to authenticated
using (
  bucket_id in ('profile-photos-private', 'reunion-photos-private')
  and ((storage.foldername(name))[1] = (select auth.uid())::text or private.is_editor((select auth.uid())))
);
create policy "Members update own private images" on storage.objects for update to authenticated
using (bucket_id in ('profile-photos-private', 'reunion-photos-private') and (storage.foldername(name))[1] = (select auth.uid())::text)
with check (bucket_id in ('profile-photos-private', 'reunion-photos-private') and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Editors manage approved book assets" on storage.objects for all to authenticated
using (bucket_id = 'book-assets-approved' and private.is_editor((select auth.uid())))
with check (bucket_id = 'book-assets-approved' and private.is_editor((select auth.uid())));
create policy "Public reads gallery objects" on storage.objects for select to anon, authenticated
using (bucket_id = 'public-gallery');
create policy "Editors manage gallery objects" on storage.objects for all to authenticated
using (bucket_id = 'public-gallery' and private.is_editor((select auth.uid())))
with check (bucket_id = 'public-gallery' and private.is_editor((select auth.uid())));

insert into public.app_settings (key, value, is_public)
values
  ('features.biographies', 'true', false),
  ('features.media_uploads', 'true', false),
  ('features.editorial_review', 'true', false),
  ('features.book_exports', 'true', false),
  ('features.public_gallery', 'false', true)
on conflict (key) do update set value = excluded.value, updated_at = now();
