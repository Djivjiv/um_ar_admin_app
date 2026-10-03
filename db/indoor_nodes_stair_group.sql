-- Stair/Elevator Group support for the floor plan editor.
-- Shared id for the same staircase/elevator across every floor
-- (e.g. BE_STAIRS_A). Only set on nodes whose label is 'stairs' or 'elevator'.
alter table indoor_nodes add column if not exists stair_group text;

create index if not exists indoor_nodes_stair_group_idx
  on indoor_nodes (stair_group)
  where stair_group is not null;
