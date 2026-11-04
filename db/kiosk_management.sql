-- ===========================================================================
-- Kiosk Management (admin app) — run in the Supabase SQL editor.
-- Safe to re-run.
-- ===========================================================================

-- 1. ended_at: the kiosk app's kiosk_sessions_tracking.sql already creates
--    it, with the counts (searches_count, routes_calculated,
--    destinations_viewed), duration_seconds and end_reason. Kept here only
--    so this file also works on an older kiosk_sessions table.
alter table public.kiosk_sessions add column if not exists ended_at timestamptz;

-- 2. The counts say how many searches there were, not what was searched.
--    "Most searched / most viewed / most requested" need the text, so the
--    kiosk app logs one row per action here. The kiosk app's kiosk_events.sql
--    defines the same table; kiosk_device_code.sql adds device_code to it.
create table if not exists public.kiosk_events (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid references public.kiosk_sessions(id) on delete cascade,
  event_type  text not null check (event_type in ('search', 'building_view', 'route')),
  -- search: the search text or picked result ("BE 215")
  -- building_view: the building name ("BE Building")
  -- route: "<from> → <to>" ("Main Gate → BE Building")
  label       text not null,
  created_at  timestamptz not null default now()
);
create index if not exists kiosk_events_type_created_idx
  on public.kiosk_events (event_type, created_at);

-- 3. One settings row (id = 1) that the kiosk app reads on start-up.
insert into public.kiosk_settings
  (id, welcome_message, disclaimer_text, app_download_url,
   idle_timeout_seconds, is_survey_enabled, announcement_text, updated_at)
select 1,
       'Welcome to the University of Mindanao! Tap to find your way.',
       'Routes are approximate. Please follow campus signs and staff directions.',
       null, 120, true, null, now()
where not exists (select 1 from public.kiosk_settings);

-- 4. Row Level Security.
--    The kiosk tablet uses the anon key: it reads settings and writes its own
--    sessions/events. The kiosk_settings and kiosk_events policies below are
--    open to every signed-in account, user-app students included.
--    db/admin_lockdown.sql replaces them with admin-only ones: run it after
--    this file, and again whenever this file is re-run.
alter table public.kiosk_settings enable row level security;
alter table public.kiosk_sessions enable row level security;
alter table public.kiosk_events   enable row level security;

drop policy if exists "kiosk_settings read" on public.kiosk_settings;
create policy "kiosk_settings read"
  on public.kiosk_settings for select using (true);
drop policy if exists "kiosk_settings admin write" on public.kiosk_settings;
create policy "kiosk_settings admin write"
  on public.kiosk_settings for all to authenticated using (true) with check (true);

drop policy if exists "kiosk_sessions kiosk insert" on public.kiosk_sessions;
create policy "kiosk_sessions kiosk insert"
  on public.kiosk_sessions for insert with check (true);
drop policy if exists "kiosk_sessions kiosk update" on public.kiosk_sessions;
create policy "kiosk_sessions kiosk update"
  on public.kiosk_sessions for update using (true) with check (true);
-- Readable by the kiosk too: it updates its own row with
-- `update ... where id = <its id>`, and that WHERE needs a SELECT policy.
-- Rows hold only counts, times and device info.
drop policy if exists "kiosk_sessions admin read" on public.kiosk_sessions;
drop policy if exists "kiosk_sessions read" on public.kiosk_sessions;
create policy "kiosk_sessions read"
  on public.kiosk_sessions for select using (true);

drop policy if exists "kiosk_events kiosk insert" on public.kiosk_events;
create policy "kiosk_events kiosk insert"
  on public.kiosk_events for insert with check (true);
drop policy if exists "kiosk_events admin read" on public.kiosk_events;
create policy "kiosk_events admin read"
  on public.kiosk_events for select to authenticated using (true);
