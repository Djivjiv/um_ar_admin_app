-- ===========================================================================
-- Admin lockdown: Row Level Security so only admins can change admin-managed
-- data or read what the public typed into the kiosk. Run in the Supabase SQL
-- editor. Safe to re-run. Runs as one transaction: if any step fails,
-- nothing changes.
--
-- RUN IT LAST, after every other SQL file in the README run order. It needs:
--   * db/user_roles.sql          public.is_admin()
--   * db/kiosk_settings.sql      kiosk_settings with exit_pin
--   * db/facilities_management.sql, db/outdoor_ar_v2.sql
--   * kiosk app: kiosk_survey.sql, kiosk_events.sql
-- If any of those is missing, step 0 stops the file with a message.
--
-- Re-run this file after re-running any of these, because each recreates an
-- open policy next to the ones below (policies add up, so one open policy
-- undoes the lockdown): db/facilities_management.sql, db/outdoor_ar_v2.sql,
-- db/kiosk_management.sql, and the kiosk app's kiosk_settings_read.sql,
-- kiosk_events.sql and kiosk_survey.sql.
--
-- BEFORE RUNNING, save the output of the schema export queries in section
-- A below. That output is the exact undo: it lists every policy as it is now.
--
-- ---------------------------------------------------------------------------
-- What each step changes, and how to undo it
-- ---------------------------------------------------------------------------
-- 1. Drops EVERY policy on these 7 tables, then creates the ones below:
--      kiosk_settings, kiosk_survey_responses, kiosk_events,
--      facilities, facility_details, outdoor_ar_nodes, outdoor_ar_edges.
--    Undo: drop the new policies (names below) and recreate the old ones
--    from the saved export. The old ones, from this repo and the kiosk repo,
--    were all "using (true)":
--      kiosk_settings          "kiosk_settings read", "kiosk_settings admin
--                              write", "kiosk can read settings"
--      kiosk_survey_responses  "kiosk can insert survey responses",
--                              "admins can read survey responses"
--      kiosk_events            "kiosk_events kiosk insert",
--                              "kiosk_events admin read"
--      facilities              "Allow all facilities"
--      facility_details        "Allow all facility_details"
--      outdoor_ar_nodes        "Allow all outdoor_ar_nodes"
--      outdoor_ar_edges        "Allow all outdoor_ar_edges"
-- 2. kiosk_settings: admins read and write. Everyone can still read it
--    through "kiosk_settings public read (until step B)", because the kiosk
--    app reads this table directly today. Step B (commented out) removes it.
--    Undo: drop the two new policies.
-- 3. kiosk_survey_responses and kiosk_events: anyone may insert (the kiosk
--    uses the anon key), only admins may read. No update or delete.
--    Undo: drop the two new policies on each.
-- 4. facilities, facility_details, outdoor_ar_nodes, outdoor_ar_edges:
--    anyone may read, only admins may insert, update or delete.
--    Undo: drop the two new policies on each.
-- 5. Creates view public.kiosk_settings_public (kiosk_settings without
--    exit_pin) and function public.check_kiosk_exit_pin(text), both usable
--    with the anon key. Nothing uses them yet: the kiosk app must be changed
--    to read the view and call the function. Undo:
--      drop view if exists public.kiosk_settings_public;
--      drop function if exists public.check_kiosk_exit_pin(text);
--
-- Not changed, on purpose:
--   * kiosk_sessions. The kiosk inserts its session row and later updates it
--     with `update ... where id = <its id>`, counting the matched rows.
--     Postgres needs a SELECT policy for that WHERE, so anon must keep
--     reading kiosk_sessions. Rows hold only counts, times and device info.
--   * navigation_sessions, sus_responses, feedback_comments, visitor_sessions
--     and user_profiles: the user app's own files already limit them.
--   * The tables in section C, whose policies we have not seen.
--
-- What the other apps write (checked in their code, Nov 2026):
--   user app  user_profiles (insert, update), navigation_sessions,
--             sus_responses, feedback_comments (insert only), and
--             visitor_sessions through start_visitor_session() and
--             visitor_session_status().
--   kiosk     kiosk_sessions (insert, update own row), kiosk_survey_responses
--             (insert), kiosk_events (insert). It reads kiosk_settings and
--             announcements.
--   Neither app writes to any table this file locks down.
--
-- What the kiosk still needs after this file, and gets:
--   * read kiosk_settings              yes (public read, until step B)
--   * insert kiosk_sessions            yes (not changed here)
--   * update its own kiosk_sessions    yes (not changed here)
--   * insert kiosk_survey_responses    yes
--   * insert kiosk_events              yes
--   * read facilities, outdoor AR      yes
-- ===========================================================================


-- ===========================================================================
-- A. SCHEMA EXPORT QUERIES. Run these first, ON THEIR OWN (select them and
--    run), and save the output. They only read. Uncomment to run.
-- ===========================================================================
-- Every policy on every public table:
--
-- select tablename, policyname, cmd, roles, qual, with_check
-- from pg_policies
-- where schemaname = 'public'
-- order by tablename, policyname;
--
-- Which public tables have Row Level Security on:
--
-- select relname as table_name, relrowsecurity as rls_on,
--        relforcerowsecurity as rls_forced
-- from pg_class c join pg_namespace n on n.oid = c.relnamespace
-- where n.nspname = 'public' and c.relkind = 'r'
-- order by relname;
--
-- Table privileges for the app roles:
--
-- select table_name, grantee, string_agg(privilege_type, ', ') as privileges
-- from information_schema.role_table_grants
-- where table_schema = 'public' and grantee in ('anon', 'authenticated')
-- group by table_name, grantee
-- order by table_name, grantee;


begin;

-- ===========================================================================
-- 0. Stop early if anything this file needs is missing.
-- ===========================================================================
do $$
declare
  missing text[] := '{}';
  t text;
begin
  if to_regprocedure('public.is_admin()') is null then
    missing := missing ||
      'function public.is_admin() (run db/user_roles.sql)'::text;
  end if;
  foreach t in array array[
    'kiosk_settings', 'kiosk_survey_responses', 'kiosk_events',
    'facilities', 'facility_details', 'outdoor_ar_nodes', 'outdoor_ar_edges'
  ] loop
    if to_regclass('public.' || t) is null then
      missing := missing || ('table public.' || t);
    end if;
  end loop;
  if to_regclass('public.kiosk_settings') is not null and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'kiosk_settings'
      and column_name = 'exit_pin'
  ) then
    missing := missing ||
      'column kiosk_settings.exit_pin (run db/kiosk_settings.sql)'::text;
  end if;
  if array_length(missing, 1) > 0 then
    raise exception 'admin_lockdown.sql needs: %. Nothing was changed.',
      array_to_string(missing, '; ');
  end if;
end $$;

-- ===========================================================================
-- 1. Drop every policy on the 7 tables, so no old open policy stays behind.
-- ===========================================================================
do $$
declare
  p record;
begin
  for p in
    select tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'kiosk_settings', 'kiosk_survey_responses', 'kiosk_events',
        'facilities', 'facility_details', 'outdoor_ar_nodes',
        'outdoor_ar_edges')
  loop
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

alter table public.kiosk_settings         enable row level security;
alter table public.kiosk_survey_responses enable row level security;
alter table public.kiosk_events           enable row level security;
alter table public.facilities             enable row level security;
alter table public.facility_details       enable row level security;
alter table public.outdoor_ar_nodes       enable row level security;
alter table public.outdoor_ar_edges       enable row level security;

-- ===========================================================================
-- 2. kiosk_settings: admins read and write.
-- ===========================================================================
create policy "kiosk_settings admin all"
  on public.kiosk_settings for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- TEMPORARY. The kiosk app reads this table directly today, exit_pin
-- included, so this keeps the kiosk working. It also leaves exit_pin
-- readable with the anon key. Step B removes it once the kiosk app uses
-- kiosk_settings_public and check_kiosk_exit_pin().
create policy "kiosk_settings public read (until step B)"
  on public.kiosk_settings for select
  to anon, authenticated
  using (true);

-- ===========================================================================
-- 3. Kiosk survey answers and usage events: the kiosk inserts, admins read.
--    Free text typed by the public, so not readable with the anon key or by
--    user-app accounts.
-- ===========================================================================
create policy "kiosk_survey_responses kiosk insert"
  on public.kiosk_survey_responses for insert
  to anon, authenticated
  with check (true);
create policy "kiosk_survey_responses admin read"
  on public.kiosk_survey_responses for select
  to authenticated
  using (public.is_admin());

create policy "kiosk_events kiosk insert"
  on public.kiosk_events for insert
  to anon, authenticated
  with check (true);
create policy "kiosk_events admin read"
  on public.kiosk_events for select
  to authenticated
  using (public.is_admin());

-- ===========================================================================
-- 4. Facilities and the outdoor AR network: everyone reads, admins write.
-- ===========================================================================
create policy "facilities public read"
  on public.facilities for select to anon, authenticated using (true);
create policy "facilities admin write"
  on public.facilities for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "facility_details public read"
  on public.facility_details for select to anon, authenticated using (true);
create policy "facility_details admin write"
  on public.facility_details for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "outdoor_ar_nodes public read"
  on public.outdoor_ar_nodes for select to anon, authenticated using (true);
create policy "outdoor_ar_nodes admin write"
  on public.outdoor_ar_nodes for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "outdoor_ar_edges public read"
  on public.outdoor_ar_edges for select to anon, authenticated using (true);
create policy "outdoor_ar_edges admin write"
  on public.outdoor_ar_edges for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ===========================================================================
-- 5. A way for the kiosk to work without reading exit_pin.
--    NOT USED YET: the kiosk app must be changed to
--      * read settings from kiosk_settings_public instead of kiosk_settings;
--      * check a typed PIN with rpc('check_kiosk_exit_pin', {p_pin: ...})
--        instead of comparing it with exit_pin itself.
--    The kiosk keeps a saved PIN for offline exit today. With the function
--    it can't, so the kiosk app also needs an offline rule (for example a
--    salted hash saved while online). That is a kiosk app decision.
-- ===========================================================================

-- Runs with its owner's rights, so it can read kiosk_settings even after
-- step B. It shows every column except exit_pin.
create or replace view public.kiosk_settings_public as
select id, welcome_message, disclaimer_text, app_download_url,
       idle_timeout_seconds, is_survey_enabled, announcement_text, updated_at
from public.kiosk_settings;

grant select on public.kiosk_settings_public to anon, authenticated;

-- True when p_pin is the PIN in the first settings row. False when no PIN
-- is set. Anyone with the anon key can call it, so a 4-digit PIN can be
-- found by trying all 10,000: use 6 to 8 digits. It never returns the PIN.
create or replace function public.check_kiosk_exit_pin(p_pin text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select s.exit_pin is not null and s.exit_pin = p_pin
     from public.kiosk_settings s
     order by s.id
     limit 1),
    false);
$$;

revoke all on function public.check_kiosk_exit_pin(text) from public;
grant execute on function public.check_kiosk_exit_pin(text)
  to anon, authenticated;

commit;

notify pgrst, 'reload schema';


-- ===========================================================================
-- B. HIDE exit_pin FROM THE PUBLIC. Commented out. Run it ONLY AFTER the
--    kiosk app reads kiosk_settings_public and calls check_kiosk_exit_pin().
--    Before that, it hides the whole settings row from the kiosk: the kiosk
--    falls back to its defaults, deletes its saved copy, and its staff exit
--    stays locked.
--    Undo: run the "public read" create policy from step 2 again.
-- ===========================================================================
-- drop policy if exists "kiosk_settings public read (until step B)"
--   on public.kiosk_settings;


-- ===========================================================================
-- C. TABLES WHOSE POLICIES WE HAVE NOT SEEN. Commented out on purpose.
--    RUN THE SCHEMA EXPORT QUERIES (section A) FIRST, and compare. No SQL
--    file in any of the three repos creates these tables or their policies,
--    so nothing here is a guess at what they are now.
--      buildings, rooms, announcements, indoor_nodes, indoor_edges,
--      outdoor_nodes, outdoor_edges, building_floors (the floors and floor
--      plans table), and also about_um, facility_content, survey_questions.
--    The user app and the kiosk only read these (the kiosk reads only
--    active announcements, see its kiosk_announcements_read.sql). The pattern
--    below is the one used in step 4. Uncomment one table at a time, only
--    once the export shows nothing else depends on its current policies, and
--    drop the old open policies by name (from the export) in the same run.
-- ===========================================================================
-- alter table public.buildings enable row level security;
-- create policy "buildings public read"
--   on public.buildings for select to anon, authenticated using (true);
-- create policy "buildings admin write"
--   on public.buildings for all to authenticated
--   using (public.is_admin()) with check (public.is_admin());
--
-- Same three statements, with the table name changed, for: rooms,
-- announcements (keep the kiosk's "active only" read policy), indoor_nodes,
-- indoor_edges, outdoor_nodes, outdoor_edges, building_floors, about_um,
-- facility_content, survey_questions.
--
-- Storage buckets (buildings, floor plan images) have their own policies on
-- storage.objects; check those in the export too.
