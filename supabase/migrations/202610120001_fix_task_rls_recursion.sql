-- Remove cross-table RLS recursion between tasks, assignments, dependencies,
-- and comments. Security-definer helpers evaluate task scope without invoking
-- the caller's row policies and expose only boolean authorization decisions.

create or replace function private.can_read_task(target_user uuid, target_task uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.tasks t
    where t.id = target_task and (
      private.is_admin(target_user)
      or private.is_committee_lead(target_user, t.committee_id)
      or t.owner_profile_id = target_user
      or exists (
        select 1 from public.task_assignees a
        where a.task_id = t.id and a.profile_id = target_user
      )
      or exists (
        select 1 from public.committee_members m
        where m.committee_id = t.committee_id and m.profile_id = target_user and m.active
      )
    )
  );
$$;

create or replace function private.can_manage_task(target_user uuid, target_task uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.tasks t
    where t.id = target_task and (
      private.is_admin(target_user)
      or private.is_committee_lead(target_user, t.committee_id)
    )
  );
$$;

revoke all on function private.can_read_task(uuid, uuid) from public;
revoke all on function private.can_manage_task(uuid, uuid) from public;
grant execute on function private.can_read_task(uuid, uuid) to authenticated;
grant execute on function private.can_manage_task(uuid, uuid) to authenticated;

drop policy "Members read relevant tasks" on public.tasks;
create policy "Members read relevant tasks" on public.tasks for select to authenticated
using (private.can_read_task((select auth.uid()), id));

drop policy "Relevant users read task assignments" on public.task_assignees;
create policy "Relevant users read task assignments" on public.task_assignees for select to authenticated
using (private.can_read_task((select auth.uid()), task_id));

drop policy "Admins and leads manage task assignments" on public.task_assignees;
create policy "Admins and leads manage task assignments" on public.task_assignees for all to authenticated
using (private.can_manage_task((select auth.uid()), task_id))
with check (private.can_manage_task((select auth.uid()), task_id));

drop policy "Relevant users read task dependencies" on public.task_dependencies;
create policy "Relevant users read task dependencies" on public.task_dependencies for select to authenticated
using (
  private.can_read_task((select auth.uid()), task_id)
  and private.can_read_task((select auth.uid()), blocking_task_id)
);

drop policy "Admins and leads manage task dependencies" on public.task_dependencies;
create policy "Admins and leads manage task dependencies" on public.task_dependencies for all to authenticated
using (private.can_manage_task((select auth.uid()), task_id))
with check (
  private.can_manage_task((select auth.uid()), task_id)
  and private.can_manage_task((select auth.uid()), blocking_task_id)
);

drop policy "Relevant users read task comments" on public.task_comments;
create policy "Relevant users read task comments" on public.task_comments for select to authenticated
using (
  author_profile_id = (select auth.uid())
  or private.is_admin((select auth.uid()))
  or (
    private.can_read_task((select auth.uid()), task_id)
    and (
      not organizer_only
      or private.can_manage_task((select auth.uid()), task_id)
    )
  )
);

drop policy "Task participants add comments" on public.task_comments;
create policy "Task participants add comments" on public.task_comments for insert to authenticated
with check (
  author_profile_id = (select auth.uid())
  and private.can_read_task((select auth.uid()), task_id)
);

insert into public.app_settings (key, value, is_public)
values ('maintenance.task_rls_fixed_at', '"2026-10-12"', false)
on conflict (key) do update set value = excluded.value, updated_at = now();
