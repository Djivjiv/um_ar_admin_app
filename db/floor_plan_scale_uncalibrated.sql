-- ===========================================================================
-- Floor plan scale: allow "not calibrated" (admin app).
-- Run in the Supabase SQL editor. Safe to re-run.
--
-- The admin app no longer writes a guessed 0.05 m/px. A floor whose
-- building_floors.meters_per_pixel is null shows "not calibrated". But the
-- column default from floor_plan_pixel_scale.sql (0.05) would still fill in
-- the guess for every NEW floor plan, so drop it.
--
-- Before running: check that the user app and kiosk app handle a null
-- meters_per_pixel (they should treat it as "not calibrated", not crash).
-- ===========================================================================

alter table public.building_floors
  alter column meters_per_pixel drop default;

-- OPTIONAL. floor_plan_pixel_scale.sql set EVERY floor to 0.05, so 0.05 is
-- usually a guess, not a measurement. To mark those floors as not
-- calibrated, uncomment and run this — but first list which floors were
-- really measured at exactly 0.05 and exclude their ids:
--
--   select id, building_id, floor_number, meters_per_pixel
--   from public.building_floors order by building_id, floor_number;
--
-- update public.building_floors
--   set meters_per_pixel = null
--   where meters_per_pixel = 0.05
--     and id not in (/* measured floor ids */ -1);

notify pgrst, 'reload schema';
