begin;

create extension if not exists pgtap with schema extensions;
select plan(2);

select results_eq(
  $$select array_agg(code order by code) from public.departments where code in ('IT', 'CSE', 'EEE', 'MECH', 'ECE', 'STAFF')$$,
  $$values (array['CSE', 'ECE', 'EEE', 'IT', 'MECH', 'STAFF']::text[])$$,
  'all six default department codes are available'
);

select results_eq(
  $$select array_agg(name order by code) from public.departments where code in ('IT', 'CSE', 'EEE', 'MECH', 'ECE', 'STAFF')$$,
  $$values (array[
    'Computer Science and Engineering',
    'Electronics and Communication Engineering',
    'Electrical and Electronics Engineering',
    'Information Technology',
    'Mechanical Engineering',
    'Staff'
  ]::text[])$$,
  'default department display names are normalized'
);

select * from finish();
rollback;

