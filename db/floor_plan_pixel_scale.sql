-- Pixel-based indoor navigation: one scale value per floor plan.
-- Indoor nodes are placed at image pixel (x, y); edge weights are pixel
-- distances. Real distance = pixels * meters_per_pixel.
-- Run in the Supabase SQL editor.
alter table public.building_floors
  add column if not exists meters_per_pixel float8 default 0.05;

update public.building_floors
  set meters_per_pixel = 0.05
  where meters_per_pixel is null;
