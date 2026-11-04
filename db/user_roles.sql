-- ===========================================================================
-- Role management guard for user_profiles (admin app Users screen).
-- Run in the Supabase SQL editor. Safe to re-run. If you ran an earlier copy
-- of this file, run this one too: the earlier guard blocked the mobile app's
-- role picker.
--
-- The admin app checks these rules before saving, but any client with the
-- anon key could skip that check, so the database enforces them too:
--   * only an active admin can change roles, approval (is_verified) or
--     is_active, with one exception below;
--   * the role must be student, employee, faculty, admin or visitor;
--   * an admin can't remove their own admin role or deactivate themselves;
--   * the last active admin can't be demoted or deactivated.
--
-- The exception is the mobile app's role picker: a user with no role yet may
-- set their own role once, to student, employee or faculty. The signed-in
-- email decides the rest, so the app can't claim more than it should:
--   * student format (see is_student_email below): student and verified;
--   * any other email: the picked role, and is_verified stays as it is. A new
--     account is unverified, which puts it in the admin app's "Pending
--     Approval" list. One an admin already approved stays approved.
-- A profile row created by the app itself is never verified unless its email
-- is in the student format, whatever the insert says.
--
-- Requests with no JWT (SQL editor, database triggers) or the service_role
-- key are not limited.
-- ===========================================================================

-- 0. first initial.lastname.idnumber@umindanao.edu.ph. The mobile app has the
--    same rule in lib/core/config/email_role_config.dart: change both together.
create or replace function public.is_student_email(address text)
returns boolean
language sql
immutable
as $$
  select coalesce(
    lower(trim(address)) ~ '^[a-z]\.[a-z]+(-[a-z]+)*\.[0-9]+@umindanao\.edu\.ph$',
    false
  );
$$;

-- 1. Is the signed-in account an active admin? Matches the profile by auth
--    uid, then by email (some profile rows are keyed on email — the admin
--    app's login does the same fallback).
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_profiles p
    where (p.id::text = auth.uid()::text
           or lower(p.email) = lower(auth.jwt() ->> 'email'))
      and lower(p.role) = 'admin'
      and p.is_active is not false
  );
$$;

-- 2. The guard, run before any update of role, is_verified or is_active.
create or replace function public.guard_user_profile_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_role text := coalesce(auth.jwt() ->> 'role', '');
  role_changed boolean := new.role is distinct from old.role;
  status_changed boolean := new.is_verified is distinct from old.is_verified
                            or new.is_active is distinct from old.is_active;
  is_self boolean := old.id::text = auth.uid()::text
                     or lower(old.email) = lower(auth.jwt() ->> 'email');
  was_active_admin boolean := lower(coalesce(old.role, '')) = 'admin'
                              and old.is_active is not false;
  loses_admin boolean := lower(coalesce(new.role, '')) <> 'admin'
                         or new.is_active is false;
begin
  if not role_changed and not status_changed then
    return new;
  end if;
  -- SQL editor (no JWT) and service_role: trusted, not limited.
  if caller_role in ('', 'service_role') then
    return new;
  end if;

  if not public.is_admin() then
    -- The mobile app's role picker: first choice only, own row, never admin.
    if role_changed
       and not status_changed
       and is_self
       and coalesce(old.role, '') = ''
       and old.is_active is not false
       and lower(coalesce(new.role, '')) in ('student', 'employee', 'faculty')
    then
      -- From the JWT: the email column can be edited by its owner.
      -- is_verified is left alone otherwise: status_changed is false here, so
      -- this can't verify anyone, and an admin's earlier approval survives.
      if public.is_student_email(auth.jwt() ->> 'email') then
        new.role := 'student';
        new.is_verified := true;
      end if;
      return new;
    end if;
    raise exception 'Only an admin can change account roles or approval.'
      using errcode = '42501';
  end if;

  if role_changed and lower(coalesce(new.role, '')) not in
     ('student', 'employee', 'faculty', 'admin', 'visitor') then
    raise exception 'Unknown role "%".', new.role
      using errcode = '22023';
  end if;

  if was_active_admin and loses_admin then
    if is_self then
      raise exception 'You can''t remove your own admin access.'
        using errcode = '42501';
    end if;
    -- Lock the admin rows so two admins demoting each other at the same
    -- moment can't both pass the check below.
    perform 1 from public.user_profiles
      where lower(role) = 'admin'
      for update;
    if not exists (
      select 1 from public.user_profiles p
      where p.id <> old.id
        and lower(p.role) = 'admin'
        and p.is_active is not false
    ) then
      raise exception 'This is the last active admin — promote another '
                      'account first.'
        using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists user_profiles_role_guard on public.user_profiles;
create trigger user_profiles_role_guard
  before update of role, is_verified, is_active on public.user_profiles
  for each row execute function public.guard_user_profile_role();

-- 2b. The same rule for a row the app creates itself on first sign-in. Rows
--     from database triggers and the SQL editor have no JWT and pass through.
create or replace function public.guard_user_profile_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_role text := coalesce(auth.jwt() ->> 'role', '');
begin
  if caller_role in ('', 'service_role') or public.is_admin() then
    return new;
  end if;
  new.is_active := true;
  if public.is_student_email(auth.jwt() ->> 'email') then
    new.role := 'student';
    new.is_verified := true;
  else
    new.role := null;
    new.is_verified := false;
  end if;
  return new;
end;
$$;

drop trigger if exists user_profiles_insert_guard on public.user_profiles;
create trigger user_profiles_insert_guard
  before insert on public.user_profiles
  for each row execute function public.guard_user_profile_insert();

-- 3. Let admins update other accounts' rows. Policies add up, so this only
--    widens access for admins and leaves existing policies as they are. If
--    Row Level Security already allows this, the policy changes nothing.
drop policy if exists "Admins can update user profiles" on public.user_profiles;
create policy "Admins can update user profiles"
  on public.user_profiles
  for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());
