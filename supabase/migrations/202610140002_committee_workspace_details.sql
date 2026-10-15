-- Privacy-safe committee detail feeds for the authenticated member workspace.
-- These functions expose only display names, department codes, committee roles,
-- and operational task fields. Private contact and profile data remain hidden.

create or replace function public.committee_workspace_members()
returns table (
  committee_id uuid,
  profile_id uuid,
  display_name text,
  department_code text,
  committee_role text,
  active boolean
)
language sql stable security definer set search_path = '' as $$
  select
    membership.committee_id,
    membership.profile_id,
    coalesce(nullif(trim(profile.preferred_name), ''), profile.full_name),
    department.code,
    membership.committee_role,
    membership.active
  from public.committee_members membership
  join public.profiles profile on profile.id = membership.profile_id
  left join public.departments department on department.id = profile.department_id
  where private.is_active_user((select auth.uid()))
    and profile.verification_status in ('invited', 'pending', 'verified')
  order by membership.committee_id,
    case membership.committee_role
      when 'lead' then 1
      when 'deputy' then 2
      when 'india_coordinator' then 3
      when 'finance_liaison' then 4
      else 5
    end,
    coalesce(nullif(trim(profile.preferred_name), ''), profile.full_name);
$$;

create or replace function public.committee_workspace_tasks()
returns table (
  id uuid,
  task_number bigint,
  committee_id uuid,
  owner_profile_id uuid,
  owner_display_name text,
  title text,
  description text,
  priority text,
  status text,
  due_date date,
  progress_note text
)
language sql stable security definer set search_path = '' as $$
  select
    task.id,
    task.task_number,
    task.committee_id,
    task.owner_profile_id,
    coalesce(nullif(trim(owner.preferred_name), ''), owner.full_name),
    task.title,
    task.description,
    task.priority,
    task.status,
    task.due_date,
    task.progress_note
  from public.tasks task
  left join public.profiles owner on owner.id = task.owner_profile_id
  where private.is_active_user((select auth.uid()))
  order by task.committee_id,
    case task.status
      when 'blocked' then 1
      when 'in_progress' then 2
      when 'ready' then 3
      when 'proposed' then 4
      when 'completed' then 5
      else 6
    end,
    task.due_date nulls last,
    task.task_number;
$$;

revoke all on function public.committee_workspace_members() from public;
revoke all on function public.committee_workspace_tasks() from public;
grant execute on function public.committee_workspace_members() to authenticated;
grant execute on function public.committee_workspace_tasks() to authenticated;

comment on function public.committee_workspace_members() is
  'Returns the privacy-safe committee roster to active authenticated members.';
comment on function public.committee_workspace_tasks() is
  'Returns committee task summaries to active authenticated members.';
