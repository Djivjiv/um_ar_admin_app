-- ===========================================================================
-- Indoor node: informational-node + is_navigable + outdoor link support.
-- Run in the Supabase SQL editor.
-- ===========================================================================

alter table public.indoor_nodes add column if not exists is_navigable     bool default true;
alter table public.indoor_nodes add column if not exists is_entrance      bool default false;
alter table public.indoor_nodes add column if not exists entrance_label   text;
alter table public.indoor_nodes add column if not exists outdoor_node_id  text;
alter table public.indoor_nodes add column if not exists room_name        text;
alter table public.indoor_nodes add column if not exists room_number      text;
alter table public.indoor_nodes add column if not exists node_description text;
alter table public.indoor_nodes add column if not exists operating_hours  text;
alter table public.indoor_nodes add column if not exists contact          text;
alter table public.indoor_nodes add column if not exists floor            int default 1;
-- 'rooms' or 'facilities' — which table linked_room_id points at
alter table public.indoor_nodes add column if not exists linked_table     text;

-- linked_room_id can point at rooms.id OR facilities.id (both int8), so it is
-- a plain bigint with no FK — linked_table ('rooms' | 'facilities') says which.
alter table public.indoor_nodes add column if not exists linked_room_id bigint;
-- If you already added an FK to rooms(id), drop it:
alter table public.indoor_nodes
  drop constraint if exists indoor_nodes_linked_room_id_fkey;

-- indoor_edges direction support
alter table public.indoor_edges add column if not exists is_two_way bool default true;

-- The Outdoor Node dropdown reads outdoor_nodes filtered by building + entrance.
-- (outdoor_node_entrances.sql already adds outdoor_nodes.is_entrance /
--  outdoor_nodes.indoor_node_id — run that first if you haven't.)
