-- ===========================================================================
-- UM-AR Nav Admin — mock data
-- 30 registered users + 10 visitor sessions + 10 kiosk sessions
-- Run this in the Supabase SQL editor (project yoqsjjnhmluqivkgiwoa).
--
-- NOTE: if public.user_profiles.id is a foreign key to auth.users(id), this
-- insert will fail. Either drop that FK for seeding, or create matching
-- auth users first. The block below assumes user_profiles.id has a
-- gen_random_uuid() default and no FK.
-- ===========================================================================

-- --- kiosk_sessions: make sure the table + columns the admin panel reads exist
create table if not exists public.kiosk_sessions (
  id               uuid primary key default gen_random_uuid(),
  started_at       timestamptz not null default now(),
  ended_at         timestamptz,
  navigation_count integer     not null default 0,
  created_at       timestamptz not null default now()
);
alter table public.kiosk_sessions add column if not exists ended_at timestamptz;
alter table public.kiosk_sessions add column if not exists navigation_count integer not null default 0;

-- ---------------------------------------------------------------------------
-- 30 registered users (student / faculty)
-- ---------------------------------------------------------------------------
insert into public.user_profiles (email, full_name, role, is_verified, is_active, created_at, last_seen)
values
  ('juan.santos.204817@umindanao.edu.ph',        'Juan Santos',         'student', true,  true,  now() - interval '172 days', now() - interval '1 day'),
  ('maria.reyes.118293@umindanao.edu.ph',        'Maria Reyes',         'faculty', true,  true,  now() - interval '240 days', now() - interval '3 hours'),
  ('jose.cruz.339104@umindanao.edu.ph',          'Jose Cruz',           'student', false, true,  now() - interval '158 days', now() - interval '5 days'),
  ('andrea.bautista.402215@umindanao.edu.ph',    'Andrea Bautista',     'student', true,  true,  now() - interval '143 days', now() - interval '12 hours'),
  ('miguel.ocampo.556730@umindanao.edu.ph',      'Miguel Ocampo',       'student', true,  true,  now() - interval '130 days', now() - interval '2 days'),
  ('sofia.garcia.667841@umindanao.edu.ph',       'Sofia Garcia',        'faculty', true,  true,  now() - interval '300 days', now() - interval '6 hours'),
  ('gabriel.mendoza.778952@umindanao.edu.ph',    'Gabriel Mendoza',     'student', false, true,  now() - interval '118 days', now() - interval '8 days'),
  ('isabella.torres.889063@umindanao.edu.ph',    'Isabella Torres',     'student', false, false, now() - interval '110 days', now() - interval '40 days'),
  ('antonio.flores.990174@umindanao.edu.ph',     'Antonio Flores',      'student', true,  true,  now() - interval '99 days',  now() - interval '1 day'),
  ('angelica.villanueva.101285@umindanao.edu.ph','Angelica Villanueva', 'faculty', true,  true,  now() - interval '265 days', now() - interval '2 hours'),
  ('carlo.ramos.212396@umindanao.edu.ph',        'Carlo Ramos',         'student', true,  true,  now() - interval '88 days',  now() - interval '4 days'),
  ('patricia.aquino.323407@umindanao.edu.ph',    'Patricia Aquino',     'student', true,  true,  now() - interval '77 days',  now() - interval '18 hours'),
  ('rafael.castillo.434518@umindanao.edu.ph',    'Rafael Castillo',     'student', false, true,  now() - interval '70 days',  null),
  ('camille.fernandez.545629@umindanao.edu.ph',  'Camille Fernandez',   'student', true,  true,  now() - interval '64 days',  now() - interval '1 day'),
  ('daniel.gonzales.656730@umindanao.edu.ph',    'Daniel Gonzales',     'faculty', true,  true,  now() - interval '210 days', now() - interval '5 hours'),
  ('nicole.delacruz.767841@umindanao.edu.ph',    'Nicole Dela Cruz',    'student', true,  true,  now() - interval '58 days',  now() - interval '3 days'),
  ('marco.rivera.878952@umindanao.edu.ph',       'Marco Rivera',        'student', false, false, now() - interval '52 days',  now() - interval '30 days'),
  ('trisha.aguilar.989063@umindanao.edu.ph',     'Trisha Aguilar',      'student', true,  true,  now() - interval '47 days',  now() - interval '22 hours'),
  ('paolo.pascual.190174@umindanao.edu.ph',      'Paolo Pascual',       'student', false, true,  now() - interval '41 days',  now() - interval '9 days'),
  ('kristine.salazar.201285@umindanao.edu.ph',   'Kristine Salazar',    'faculty', true,  true,  now() - interval '180 days', now() - interval '1 hour'),
  ('enrico.domingo.312396@umindanao.edu.ph',     'Enrico Domingo',      'student', true,  true,  now() - interval '36 days',  now() - interval '2 days'),
  ('danica.navarro.423407@umindanao.edu.ph',     'Danica Navarro',      'student', true,  false, now() - interval '33 days',  now() - interval '15 days'),
  ('lorenzo.delrosario.534518@umindanao.edu.ph', 'Lorenzo Del Rosario', 'student', false, true,  now() - interval '29 days',  now() - interval '6 days'),
  ('mariel.mercado.645629@umindanao.edu.ph',     'Mariel Mercado',      'faculty', true,  true,  now() - interval '155 days', now() - interval '4 hours'),
  ('francis.tan.756730@umindanao.edu.ph',        'Francis Tan',         'student', true,  true,  now() - interval '25 days',  now() - interval '1 day'),
  ('aira.lim.867841@umindanao.edu.ph',           'Aira Lim',            'student', false, true,  now() - interval '21 days',  null),
  ('joshua.gutierrez.978952@umindanao.edu.ph',   'Joshua Gutierrez',    'student', true,  true,  now() - interval '17 days',  now() - interval '12 hours'),
  ('bea.espinosa.189063@umindanao.edu.ph',       'Bea Espinosa',        'faculty', true,  true,  now() - interval '133 days', now() - interval '3 hours'),
  ('kevin.manalo.290174@umindanao.edu.ph',       'Kevin Manalo',        'student', false, false, now() - interval '12 days',  now() - interval '8 days'),
  ('regine.diaz.301285@umindanao.edu.ph',        'Regine Diaz',         'faculty', true,  true,  now() - interval '95 days',  now() - interval '2 hours');

-- ---------------------------------------------------------------------------
-- 10 visitor sessions (4 active, 6 expired) — started in the last 7 days
-- ---------------------------------------------------------------------------
insert into public.visitor_sessions (device_id, started_at, expires_at, is_expired)
values
  ('AND-8842', now() - interval '25 minutes',        now() + interval '95 minutes',                          false),
  ('IOS-1195', now() - interval '1 hour',            now() + interval '1 hour',                              false),
  ('AND-6620', now() - interval '10 minutes',        now() + interval '110 minutes',                         false),
  ('AND-3391', now() - interval '45 minutes',        now() + interval '75 minutes',                          false),
  ('IOS-7714', now() - interval '2 days',            now() - interval '2 days'  + interval '2 hours',        true),
  ('AND-2205', now() - interval '5 days',            now() - interval '5 days'  + interval '2 hours',        true),
  ('AND-9930', now() - interval '3 days',            now() - interval '3 days'  + interval '90 minutes',     true),
  ('IOS-4417', now() - interval '6 days',            now() - interval '6 days'  + interval '2 hours',        true),
  ('AND-1188', now() - interval '4 days',            now() - interval '4 days'  + interval '150 minutes',    true),
  ('AND-5563', now() - interval '1 day 6 hours',     now() - interval '1 day 4 hours',                        true);

-- ---------------------------------------------------------------------------
-- 10 kiosk sessions (3 active, 7 ended) — started in the last 7 days
-- ---------------------------------------------------------------------------
insert into public.kiosk_sessions (started_at, ended_at, navigation_count)
values
  (now() - interval '20 minutes',   null,                                                 2),
  (now() - interval '5 minutes',    null,                                                 0),
  (now() - interval '50 minutes',   null,                                                 5),
  (now() - interval '1 day',        now() - interval '1 day'   + interval '35 minutes',   4),
  (now() - interval '2 days',       now() - interval '2 days'  + interval '1 hour',       7),
  (now() - interval '3 days',       now() - interval '3 days'  + interval '22 minutes',   1),
  (now() - interval '4 days',       now() - interval '4 days'  + interval '48 minutes',   6),
  (now() - interval '5 days',       now() - interval '5 days'  + interval '15 minutes',   2),
  (now() - interval '6 days',       now() - interval '6 days'  + interval '40 minutes',   3),
  (now() - interval '12 hours',     now() - interval '12 hours' + interval '28 minutes',  8);
