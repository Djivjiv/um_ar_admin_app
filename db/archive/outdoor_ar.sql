-- ===========================================================================
-- ARCHIVED: do not run; it would recreate outdoor_ar_points.
--
-- outdoor_ar_v2.sql dropped that table and replaced it with the independent
-- outdoor_ar_nodes / outdoor_ar_edges network. This file is kept for history.
-- Its building columns moved to db/building_ar_columns.sql.
-- ===========================================================================

-- ===========================================================================
-- Outdoor AR (admin app "Outdoor AR" screen + user-app AR overlay).
-- ===========================================================================

-- 1. Dense points along each outdoor edge, so AR arrows follow the walkway
--    instead of pointing straight at the destination.
--    Points of one edge are ordered by sort_index from the edge's from_node
--    to its to_node. The two end nodes themselves are NOT stored here — the
--    full walkway is: from_node → points (by sort_index) → to_node.
--    (outdoor_edges.id is uuid, so edge_id is uuid.)
create table if not exists public.outdoor_ar_points (
  id          bigserial primary key,
  edge_id     uuid not null references public.outdoor_edges(id) on delete cascade,
  lat         double precision not null,
  lng         double precision not null,
  sort_index  int not null default 0,
  is_active   boolean default true,
  created_at  timestamptz default now()
);
create index if not exists outdoor_ar_points_edge_sort_idx
  on public.outdoor_ar_points (edge_id, sort_index);

-- 2. Per-building AR destination marker settings.
alter table public.buildings add column if not exists ar_emoji text default '📍';
alter table public.buildings add column if not exists ar_label text;
alter table public.buildings add column if not exists ar_arrival_radius_m double precision default 8;

-- 3. RLS — same open policy as the other admin-managed tables.
--    Postgres has no `CREATE POLICY IF NOT EXISTS`, so drop-then-create.
alter table public.outdoor_ar_points enable row level security;
drop policy if exists "Allow all outdoor_ar_points" on public.outdoor_ar_points;
create policy "Allow all outdoor_ar_points"
  on public.outdoor_ar_points for all using (true) with check (true);

-- Make the new table visible to PostgREST immediately.
notify pgrst, 'reload schema';
