-- ===========================================================================
-- Building-entrance support for outdoor_nodes + buildings select policy.
-- Run in the Supabase SQL editor.
-- ===========================================================================

alter table public.outdoor_nodes add column if not exists is_entrance     bool default false;
alter table public.outdoor_nodes add column if not exists entrance_label  text;
alter table public.outdoor_nodes add column if not exists indoor_node_id  text;
alter table public.outdoor_nodes add column if not exists floor           int default 1;

-- Optional: index for "entrances of a building" lookups
create index if not exists outdoor_nodes_entrance_idx
  on public.outdoor_nodes (building_id) where is_entrance;

-- ---------------------------------------------------------------------------
-- RLS: allow reading buildings (needed for the entrance building dropdown).
-- Postgres has no `CREATE POLICY IF NOT EXISTS`, so drop-then-create.
-- ---------------------------------------------------------------------------
alter table public.buildings enable row level security;
drop policy if exists "Allow select buildings admin" on public.buildings;
create policy "Allow select buildings admin"
  on public.buildings for select using (true);

-- The embedded select `outdoor_nodes(*, buildings(...))` needs a FK from
-- outdoor_nodes.building_id -> buildings.id. Add it if it does not exist:
-- do $$ begin
--   alter table public.outdoor_nodes
--     add constraint outdoor_nodes_building_id_fkey
--     foreign key (building_id) references public.buildings(id) on delete set null;
-- exception when duplicate_object then null; end $$;
