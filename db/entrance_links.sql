-- ===========================================================================
-- Entrance pairs: outdoor_nodes.indoor_node_id <-> indoor_nodes.outdoor_node_id
-- Run in the Supabase SQL editor, one step at a time. Nothing here is needed
-- for the admin app to work; it enforces the rules in the database too.
--
-- No new column: indoor_nodes.outdoor_node_id (db/indoor_nodes_infonodes.sql)
-- already points back. Run that file first if the column is missing.
-- ===========================================================================

-- 1. Report. Outdoor entrances that break a rule. Read-only.
select o.id as outdoor_id,
       o.building_id,
       o.indoor_node_id,
       case
         when o.indoor_node_id is null or o.indoor_node_id = ''
           then 'missing indoor node'
         when i.id is null
           then 'indoor node no longer exists'
         when coalesce(i.building_id, f.building_id) is distinct from o.building_id
           then 'indoor node in a different building'
         when count(*) over (partition by o.indoor_node_id) > 1
           then 'indoor node shared with another entrance'
         when i.outdoor_node_id is distinct from o.id
           then 'reverse link out of step'
         else 'linked'
       end as status
from public.outdoor_nodes o
left join public.indoor_nodes i on i.id = o.indoor_node_id
left join public.building_floors f on f.id = i.floor_plan_id
where o.is_entrance
order by o.building_id, o.id;

-- 2. OPTIONAL. Backfill the reverse side of links saved before the admin app
--    kept both sides in step. Review step 1 first; this skips shared targets.
--
-- update public.indoor_nodes i
--   set outdoor_node_id = o.id, is_entrance = true
--   from public.outdoor_nodes o
--   where o.is_entrance
--     and o.indoor_node_id = i.id
--     and i.outdoor_node_id is distinct from o.id
--     and (select count(*) from public.outdoor_nodes x
--          where x.is_entrance and x.indoor_node_id = o.indoor_node_id) = 1;

-- 3. OPTIONAL. One outdoor entrance per indoor node, enforced by the database.
--    This fails while step 1 still lists a shared indoor node, so fix those
--    first. The admin app checks this rule too, but two admins saving at the
--    same moment could both pass that check.
--
--    Check for duplicates first. This is read-only, and uses the index's own
--    rule, so every row it returns would make the index fail:
--
-- select indoor_node_id,
--        count(*) as entrances,
--        array_agg(id order by id) as outdoor_node_ids
-- from public.outdoor_nodes
-- where is_entrance and indoor_node_id is not null
-- group by indoor_node_id
-- having count(*) > 1;
--
--    No rows: safe to create the index. Any rows: keep one outdoor entrance
--    for each indoor node (re-link the others in the campus map editor), then
--    run the check again.
--
-- create unique index if not exists outdoor_nodes_one_entrance_per_indoor_node
--   on public.outdoor_nodes (indoor_node_id)
--   where is_entrance and indoor_node_id is not null;
