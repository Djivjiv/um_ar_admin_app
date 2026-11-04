# UM-AR Nav Admin

The admin panel for **UM-AR Nav**, a mobile AR navigation system for the
University of Mindanao Matina Campus (thesis project).

UM-AR Nav is three Flutter apps that share one Supabase backend:

- **User app**: indoor and outdoor navigation with AR, for students and visitors.
- **Kiosk app**: a campus kiosk for visitors.
- **Admin app** (this repository): manages the campus data the other two apps read.

## What the admin app does

- Buildings, rooms, facilities and context content
- Campus map editor (outdoor nodes and edges) and the outdoor AR path editor
- Floor plans: upload, georeferencing, and the indoor node/edge editor
- Announcements and About UM content
- Users and visitor sessions
- Kiosk management (settings, usage, survey summary)
- Analytics, the dashboard and SUS survey responses, with Excel export

Only accounts whose `user_profiles.role` is `admin` and that are active can
sign in.

## Platforms

Windows desktop and web. There are no Android or iOS targets.

## Running

```sh
flutter pub get
flutter run -d windows --dart-define=MAPTILER_KEY=your_key
# or: flutter run -d chrome --dart-define=MAPTILER_KEY=your_key
```

The Supabase project URL and anon key are in
`lib/core/config/supabase_config.dart`.

### MapTiler key

The MapTiler API key is not in the source. Pass it at build time with
`--dart-define=MAPTILER_KEY=your_key`, on every `flutter run` and
`flutter build`. Create a key at <https://cloud.maptiler.com/account/keys/>.

Without a key the app still runs, but the Campus Map and georeferencing maps
have no tiles, and Outdoor AR offers only Esri and OpenStreetMap. Each of those
screens and the dashboard's system status show a message saying the key is
missing.

The key is compiled into the app, so anyone can read it from a web build.
Restrict it to your domains in the MapTiler dashboard.

## Release builds

```sh
flutter build windows --dart-define=MAPTILER_KEY=your_key
flutter build web --dart-define=MAPTILER_KEY=your_key
```

## Database

The three apps share one database, and their SQL files are run by hand in the
Supabase SQL editor. Nothing runs them automatically. The files live in three
repositories: `db/` here, and `supabase/` in the user app and the kiosk app.
Files in `db/archive/` are kept for reference only. Do not run them.

### Before you start

No SQL file in any of the three repositories creates the base tables, so they
must already exist: `buildings`, `rooms`, `facilities`, `building_floors`,
`indoor_nodes`, `outdoor_nodes`, `user_profiles` and others.

`kiosk_settings` is created by `db/kiosk_settings.sql` (step 11). Steps 13, 21
and 22 fail without it.

### SQL files, in run order

The "From" column says where the file lives: **admin** is `db/` in this
repository, **user** is `supabase/` in the user app and **kiosk** is `supabase/`
in the kiosk app.

| # | From | File | What it does | Notes |
|---|------|------|--------------|-------|
| 1 | admin | `facilities_management.sql` | Facility policies and the `facility_details` link | Its open policy is replaced by step 31 |
| 2 | admin | `floor_plan_pixel_scale.sql` | Adds `meters_per_pixel` | Only on a new database: it resets empty scales to 0.05 |
| 3 | admin | `floor_plan_scale_uncalibrated.sql` | Lets a floor be "not calibrated" | Check the user and kiosk apps first; its cleanup step is optional |
| 4 | admin | `outdoor_node_entrances.sql` | Entrance columns on `outdoor_nodes` | |
| 5 | admin | `indoor_nodes_infonodes.sql` | Info nodes, room links, `outdoor_node_id` | After 4 |
| 6 | admin | `indoor_nodes_stair_group.sql` | Stair and elevator groups | |
| 7 | admin | `building_label_editing.sql` | Building label position and display name | |
| 8 | admin | `building_ar_columns.sql` | AR marker columns on `buildings` | |
| 9 | admin | `outdoor_ar_v2.sql` | AR path network | Drops `outdoor_ar_points`. Its open policy is replaced by step 31 |
| 10 | admin | `survey_questions_and_foodcourt_cleanup.sql` | SUS question table | **Also deletes food court rows from `rooms`.** Read it first |
| 11 | admin | `kiosk_settings.sql` | Creates `kiosk_settings`, including `exit_pin` | Before 13, 21 and 22. Sets no PIN |
| 12 | kiosk | `kiosk_sessions_tracking.sql` | Creates `kiosk_sessions`, its tracking columns and policies | Before 13, 14 and 15 |
| 13 | admin | `kiosk_management.sql` | Kiosk events, settings row and policies | After 11 and 12 |
| 14 | kiosk | `kiosk_events.sql` | Lets the kiosk add `kiosk_events` rows | After 12 |
| 15 | kiosk | `kiosk_survey.sql` | Kiosk survey table | After 12 |
| 16 | kiosk | `kiosk_offline_queue.sql` | Stops re-sent survey answers being stored twice | Optional. After 15 |
| 17 | kiosk | `kiosk_device_code.sql` | Adds `device_code` to kiosk survey answers and events | **Lives in the kiosk repo.** After 14 and 15. The admin app shows its first 8 characters, and works without it |
| 18 | admin | `access_level.sql` | `access_level` on rooms and facilities | |
| 19 | admin | `user_roles.sql` | Role guard, `is_admin()` and admin update policy | Re-run if you ran an earlier copy |
| 20 | admin | `user_access_backfill.sql` | Verifies older student-format accounts | **Run once only**, after 19 and before releasing the user app version that enforces `is_verified`. Repeating it undoes later decisions |
| 21 | kiosk | `kiosk_settings_read.sql` | Lets the kiosk read `kiosk_settings` | After 11 |
| 22 | kiosk | `kiosk_exit_pin.sql` | Adds `exit_pin` and its format check | After 21. Step 11 already adds both, so this adds nothing new. Set the PIN in Kiosk Management > Settings. Until then the kiosk exit stays locked |
| 23 | kiosk | `kiosk_announcements_read.sql` | Lets the kiosk read `announcements` | |
| 24 | admin | `indoor_node_links.sql` | Clears links to deleted or inactive rooms | Its report query runs too |
| 25 | admin | `entrance_links.sql` | Entrance link report | Optional steps are commented out. After 5 |
| 26 | admin or user | `feedback_comments.sql` | Suggestions and comments table | After 19. **Run one copy only**: both define the same table and policies |
| 27 | user | `navigation_evaluation.sql` | Trip and SUS columns, policies and metric views | The Analytics and Dashboard trip counts need it |
| 28 | user | `visitor_sessions.sql` | Server-timed visitor sessions and `is_visitor` | After 19 and 27. "Continue as Visitor" fails until this has run |
| 29 | user | `sus_once_per_person.sql` | Server check and unique rule for one SUS per person | After 27. Run **one section at a time**: section 2 fails if duplicates exist, and the file shows how to look for them |
| 30 | admin | `floor_plan_distances.sql` | Distance measurements behind the floor plan editor's Add distance and Check distance | After 19: its policy needs `is_admin()`. Admins only. The editor's other tools work without it |
| 31 | admin | `admin_lockdown.sql` | Admin-only writes on facilities and the AR network; admin-only reads of kiosk answers, events and settings | **Run last**, after saving the output of its section A queries. Re-run it after re-running 1, 9, 13, 14, 15 or 21. Its step B and section C are commented out: read them first |

`admin_lockdown.sql` still lets the public read `kiosk_settings`, `exit_pin`
included, because the kiosk app reads that table directly. Its step B hides
it. Run step B only once the kiosk app reads `kiosk_settings_public` and
checks the PIN with `check_kiosk_exit_pin()`: before that, step B locks the
kiosk exit.

Until step 27 has run and trips are logged, the Analytics navigation metrics
show "No data yet" and list the columns they expect.

Data files, only when you need them:

- `db/seed_mock_data.sql`: fake users and sessions. Never run it on real data.
  It also creates `kiosk_sessions` if that table is missing.
- `db/be_floors_3_4_nodes.sql`: nodes and edges for BE Building floors 3 and 4,
  tied to floor plan ids 6 and 7. Check those ids first.

## Tests

```sh
flutter analyze
flutter test
```
