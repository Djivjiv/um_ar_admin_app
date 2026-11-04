-- ===========================================================================
-- Keeps indoor_nodes.linked_room_id from dangling.
-- Run in the Supabase SQL editor. Safe to re-run.
--
-- linked_room_id can point at rooms or facilities (see linked_table), so it
-- has no foreign key. The admin app unlinks nodes itself, but it can't do so
-- in one transaction, and it isn't the only way a row can go: a building
-- delete can cascade to its rooms. These triggers clear the link in the same
-- transaction as the delete or deactivation, whatever caused it.
-- ===========================================================================

-- 1. Clears links when a room or facility is deleted or made inactive.
create or replace function public.clear_indoor_node_links()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE'
     and (new.is_active is not false or old.is_active is false) then
    return null;
  end if;

  update public.indoor_nodes n
    set linked_room_id = null,
        linked_table = null
    where n.linked_room_id = old.id
      and case tg_table_name
            when 'rooms'
              then n.linked_table is null or n.linked_table = 'rooms'
            else n.linked_table = 'facilities'
          end;
  return null;
end;
$$;

drop trigger if exists rooms_clear_indoor_links on public.rooms;
create trigger rooms_clear_indoor_links
  after delete or update of is_active on public.rooms
  for each row execute function public.clear_indoor_node_links();

drop trigger if exists facilities_clear_indoor_links on public.facilities;
create trigger facilities_clear_indoor_links
  after delete or update of is_active on public.facilities
  for each row execute function public.clear_indoor_node_links();

-- 2. Links that are already broken: run this to see them. The floor plan
--    editor also shows them per floor, with a "Clear links" button.
select n.id,
       n.floor_plan_id,
       n.name,
       n.linked_room_id,
       coalesce(n.linked_table, 'rooms') as linked_table
from public.indoor_nodes n
left join public.rooms r
  on coalesce(n.linked_table, 'rooms') = 'rooms' and r.id = n.linked_room_id
left join public.facilities f
  on n.linked_table = 'facilities' and f.id = n.linked_room_id
where n.linked_room_id is not null
  and (r.id is null or r.is_active is false)
  and (f.id is null or f.is_active is false)
order by n.floor_plan_id, n.id;

-- 3. OPTIONAL. Clears every link listed by step 2 in one go. Review that list
--    first, then uncomment.
--
-- update public.indoor_nodes n
--   set linked_room_id = null, linked_table = null
--   where n.linked_room_id is not null
--     and not exists (
--       select 1 from public.rooms r
--       where coalesce(n.linked_table, 'rooms') = 'rooms'
--         and r.id = n.linked_room_id
--         and r.is_active is not false
--     )
--     and not exists (
--       select 1 from public.facilities f
--       where n.linked_table = 'facilities'
--         and f.id = n.linked_room_id
--         and f.is_active is not false
--     );
