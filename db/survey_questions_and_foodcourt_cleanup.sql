-- ===========================================================================
-- 1. survey_questions table for the SUS "Survey Questions" manager
--    (the admin app inserts the 10 default SUS statements automatically the
--     first time the table is empty).
-- ===========================================================================
create table if not exists public.survey_questions (
  id              uuid primary key default gen_random_uuid(),
  question_number int not null,
  question_text   text not null,
  scale           int  default 5,
  is_active       bool default true,
  updated_at      timestamptz default now()
);

-- Optional: keep one row per question number
create unique index if not exists survey_questions_number_key
  on public.survey_questions (question_number);

-- ===========================================================================
-- 2. Remove rooms attached to Food Court 1 / Food Court 2 (they have no rooms)
-- ===========================================================================
delete from public.rooms
where building_id in (
  select id from public.buildings where name ilike '%food court%'
);
