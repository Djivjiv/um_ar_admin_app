-- ===========================================================================
-- Access level for facilities and rooms (admin app forms, lists and filters).
-- Run in the Supabase SQL editor. Safe to re-run.
--
-- Values: public, students_and_faculty, staff_only. Default: public.
--
-- rooms may already have this column: the admin app has always saved a
-- free-text access_level there, and the user app's AR card prints it (for
-- example "Access: Faculty only"). So this file does NOT rewrite existing
-- values or add a CHECK constraint yet:
--   * rewriting them would change what the user app shows;
--   * a CHECK would reject saving any room that still has an older value.
-- Steps 4 and 5 below are optional and commented out for that reason.
--
-- What users see after running it: nothing changes. The AR card hides
-- "public" and empty values. It does print other values as they are, so a
-- room set to staff_only shows "Access: staff_only" there.
-- ===========================================================================

-- 1. Add the column. IF NOT EXISTS keeps any rooms column already there.
alter table public.facilities
  add column if not exists access_level text default 'public';
alter table public.rooms
  add column if not exists access_level text default 'public';

-- 2. A rooms column that already existed gets no default from step 1.
alter table public.facilities alter column access_level set default 'public';
alter table public.rooms alter column access_level set default 'public';

-- 3. Fill empty rows. Empty and public look the same to the user app.
update public.facilities set access_level = 'public'
  where access_level is null or btrim(access_level) = '';
update public.rooms set access_level = 'public'
  where access_level is null or btrim(access_level) = '';

-- Make the new column visible to PostgREST immediately.
notify pgrst, 'reload schema';

-- 4. OPTIONAL. Older free-text values, to review. Change them in the admin
--    app, or map them here once the user app is ready for the new values.
--
-- select 'rooms' as source, access_level, count(*)
--   from public.rooms
--   where access_level not in ('public', 'students_and_faculty', 'staff_only')
--   group by access_level
-- union all
-- select 'facilities', access_level, count(*)
--   from public.facilities
--   where access_level not in ('public', 'students_and_faculty', 'staff_only')
--   group by access_level;

-- 5. OPTIONAL. Only once step 4 returns no rows.
--
-- alter table public.facilities
--   add constraint facilities_access_level_check
--   check (access_level in ('public', 'students_and_faculty', 'staff_only'));
-- alter table public.rooms
--   add constraint rooms_access_level_check
--   check (access_level in ('public', 'students_and_faculty', 'staff_only'));
