-- ===========================================================================
-- Real-world distances measured between two nodes of a floor plan (admin app).
-- Run in the Supabase SQL editor. Safe to re-run.
--
-- RUN db/user_roles.sql FIRST: the policy below needs public.is_admin().
--
-- The floor plan editor's "Add distance" writes here, and the floor's
-- building_floors.meters_per_pixel is worked out from the counted rows:
--   meters_per_pixel = total real_meters / total pixel distance
-- Pixel distances are not stored: they come from the two nodes' x/y, so a
-- moved node can't leave a stale value behind.
--
-- The two nodes don't need an edge between them, and the same pair can be
-- measured more than once. `ignored` keeps a row but leaves it out of the
-- average. Deleting either node, or the floor plan, deletes the row.
--
-- The foreign keys need indoor_nodes.id and building_floors.id to be primary
-- keys. If this fails with "no unique constraint matching given keys", that
-- table's id isn't one.
-- ===========================================================================

create table if not exists public.floor_plan_distances (
  id uuid primary key default gen_random_uuid(),
  floor_plan_id bigint not null
    references public.building_floors (id) on delete cascade,
  node_a_id text not null
    references public.indoor_nodes (id) on delete cascade,
  node_b_id text not null
    references public.indoor_nodes (id) on delete cascade,
  real_meters double precision not null check (real_meters > 0),
  ignored boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint floor_plan_distances_two_nodes check (node_a_id <> node_b_id)
);

create index if not exists floor_plan_distances_floor_plan_id_idx
  on public.floor_plan_distances (floor_plan_id);

-- Keeps updated_at right whichever client writes.
create or replace function public.touch_floor_plan_distance()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists floor_plan_distances_touch on public.floor_plan_distances;
create trigger floor_plan_distances_touch
  before update on public.floor_plan_distances
  for each row execute function public.touch_floor_plan_distance();

-- Only active admins can read or write. The user and kiosk apps never use this
-- table: they read the result from building_floors.meters_per_pixel.
alter table public.floor_plan_distances enable row level security;

grant select, insert, update, delete
  on public.floor_plan_distances to authenticated;

drop policy if exists "Admins manage floor plan distances"
  on public.floor_plan_distances;
create policy "Admins manage floor plan distances"
  on public.floor_plan_distances
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

notify pgrst, 'reload schema';
