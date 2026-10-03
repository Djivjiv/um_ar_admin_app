-- Facility Management screen — RLS policies + the FK/uniqueness PostgREST
-- needs to embed facility_details inside the facilities query.

alter table facilities enable row level security;
alter table facility_details enable row level security;

drop policy if exists "Allow all facilities" on facilities;
create policy "Allow all facilities"
  on facilities for all using (true) with check (true);

drop policy if exists "Allow all facility_details" on facility_details;
create policy "Allow all facility_details"
  on facility_details for all using (true) with check (true);

-- PostgREST can only embed facility_details(...) if it sees a real FK.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'facility_details_facility_id_fkey'
  ) then
    alter table facility_details
      add constraint facility_details_facility_id_fkey
      foreign key (facility_id) references facilities(id) on delete cascade;
  end if;
end $$;

-- One details row per facility → PostgREST embeds it as an object, not a list.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'facility_details_facility_id_key'
  ) then
    alter table facility_details
      add constraint facility_details_facility_id_key unique (facility_id);
  end if;
end $$;
