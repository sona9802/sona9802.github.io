begin;

create extension if not exists pgtap with schema extensions;
select plan(40);

select has_table('public', 'committees', 'committees table exists');
select has_table('public', 'committee_members', 'committee memberships table exists');
select has_table('public', 'contact_attempts', 'department outreach table exists');
select has_table('public', 'tasks', 'tasks table exists');
select has_table('public', 'task_assignees', 'task assignees table exists');
select has_table('public', 'task_dependencies', 'task dependencies table exists');
select has_table('public', 'task_comments', 'task comments table exists');
select has_table('public', 'announcements', 'managed announcements table exists');
select has_table('public', 'biographies', 'biographies table exists');
select has_table('public', 'media_assets', 'media metadata table exists');
select has_table('public', 'content_exports', 'content export table exists');
select has_table('public', 'notifications', 'notifications table exists');
select has_table('public', 'faculty_staff', 'faculty and staff table exists');
select has_table('public', 'program_items', 'detailed program table exists');
select has_table('public', 'volunteer_shifts', 'volunteer shifts table exists');
select has_table('public', 'shift_assignments', 'shift assignments table exists');
select has_table('public', 'checkins', 'check-in table exists');
select has_table('public', 'operational_contacts', 'operational contacts table exists');
select has_table('public', 'finance_summaries', 'finance summaries table exists');
select has_table('public', 'feedback_submissions', 'feedback table exists');
select has_table('public', 'data_requests', 'data requests table exists');
select has_table('public', 'retention_policies', 'retention policy table exists');

select has_function('public', 'create_task', 'audited task creation function exists');
select has_function('public', 'update_task_progress', 'scoped task progress function exists');
select has_function('public', 'member_directory', 'privacy-aware directory function exists');
select has_function('public', 'organizer_dashboard', 'organizer dashboard function exists');
select has_function('public', 'department_coverage', 'department coverage report exists');
select has_function('public', 'set_user_role', 'audited role-management function exists');
select has_function('public', 'save_biography_draft', 'biography draft function exists');
select has_function('public', 'review_biography', 'biography review function exists');
select has_function('public', 'register_media_asset', 'media registration function exists');
select has_function('public', 'review_media_asset', 'media moderation function exists');
select has_function('public', 'generate_book_export', 'consent-filtered export function exists');
select has_function('public', 'editor_profile_labels', 'privacy-safe editor labels function exists');
select has_function('public', 'check_in_attendee', 'event check-in function exists');
select has_function('public', 'event_operations_dashboard', 'event dashboard function exists');
select has_function('public', 'event_operator_profile_labels', 'event operator labels function exists');

select results_eq(
  $$select count(*)::bigint from storage.buckets where id in ('profile-photos-private', 'reunion-photos-private', 'book-assets-approved', 'public-gallery')$$,
  'values (4::bigint)',
  'all required storage buckets exist'
);
select results_eq(
  $$select count(*)::bigint from public.committees$$,
  'values (7::bigint)',
  'seven functional committees are seeded'
);
select results_eq(
  $$select count(*)::bigint from public.retention_policies$$,
  'values (5::bigint)',
  'provisional retention categories are recorded'
);

select * from finish();
rollback;
