-- ===========================================================================
-- Outdoor AR v2 — an independent AR path network (admin "Outdoor AR" screen).
-- Not derived from outdoor_nodes / outdoor_edges.
-- Run in the Supabase SQL editor. Safe to re-run.
-- The building AR columns (ar_emoji, ar_label, ar_arrival_radius_m) are kept
-- as they are; they live in building_ar_columns.sql. Do not run the archived
-- archive/outdoor_ar.sql: it would recreate the table dropped below.
-- ===========================================================================

-- 1. v1 dense points along outdoor_edges are replaced by this network.
drop table if exists public.outdoor_ar_points;

-- 2. Nodes.
create table if not exists public.outdoor_ar_nodes (
  id          uuid primary key default gen_random_uuid(),
  lat         double precision not null,
  lng         double precision not null,
  label       text,
  node_type   text not null default 'path'
              check (node_type in ('path', 'building', 'junction')),
  is_active   boolean default true,
  created_at  timestamptz default now()
);

-- building_id must have the same type as buildings.id — read it from the
-- catalog instead of assuming int4 vs int8.
do $$
declare
  id_type text;
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'outdoor_ar_nodes'
      and column_name = 'building_id'
  ) then
    select format_type(a.atttypid, a.atttypmod) into id_type
    from pg_attribute a
    where a.attrelid = 'public.buildings'::regclass
      and a.attname = 'id';
    execute format(
      'alter table public.outdoor_ar_nodes add column building_id %s '
      'references public.buildings(id) on delete set null',
      id_type);
  end if;
end $$;

create index if not exists outdoor_ar_nodes_building_idx
  on public.outdoor_ar_nodes (building_id) where building_id is not null;

-- 3. Edges (undirected: the user app may walk them either way).
create table if not exists public.outdoor_ar_edges (
  id          uuid primary key default gen_random_uuid(),
  from_node   uuid not null references public.outdoor_ar_nodes(id) on delete cascade,
  to_node     uuid not null references public.outdoor_ar_nodes(id) on delete cascade,
  weight_m    double precision,
  is_active   boolean default true,
  check (from_node <> to_node)
);
create index if not exists outdoor_ar_edges_from_idx on public.outdoor_ar_edges (from_node);
create index if not exists outdoor_ar_edges_to_idx   on public.outdoor_ar_edges (to_node);

-- 4. RLS — same open policy as the other admin-managed tables.
--    Postgres has no `CREATE POLICY IF NOT EXISTS`, so drop-then-create.
alter table public.outdoor_ar_nodes enable row level security;
drop policy if exists "Allow all outdoor_ar_nodes" on public.outdoor_ar_nodes;
create policy "Allow all outdoor_ar_nodes"
  on public.outdoor_ar_nodes for all using (true) with check (true);

alter table public.outdoor_ar_edges enable row level security;
drop policy if exists "Allow all outdoor_ar_edges" on public.outdoor_ar_edges;
create policy "Allow all outdoor_ar_edges"
  on public.outdoor_ar_edges for all using (true) with check (true);

-- Make the new tables visible to PostgREST immediately.
notify pgrst, 'reload schema';
