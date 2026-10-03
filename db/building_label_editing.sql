-- Building label editing (campus map editor): draggable labels + custom
-- display text, independent of the building's own lat/lng.
alter table buildings add column if not exists label_lat float8;
alter table buildings add column if not exists label_lng float8;
alter table buildings add column if not exists display_name text;
