-- ===========================================================================
-- Per-building AR destination marker settings (admin "Outdoor AR" screen and
-- the user app's AR overlay).
-- Run in the Supabase SQL editor. Safe to re-run.
--
-- Moved out of db/archive/outdoor_ar.sql, which must not be run. A database
-- that already ran that file has these columns, and this changes nothing.
-- ===========================================================================

alter table public.buildings add column if not exists ar_emoji text default '📍';
alter table public.buildings add column if not exists ar_label text;
alter table public.buildings add column if not exists ar_arrival_radius_m double precision default 8;

-- Make the new columns visible to PostgREST immediately.
notify pgrst, 'reload schema';
