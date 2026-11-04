-- ===========================================================================
-- One-time clean-up for the mobile app's account check. Run ONCE, after
-- db/user_roles.sql, and before releasing the version that enforces
-- is_verified. NOT safe to repeat: it would undo an admin's later decision to
-- unverify one of these students.
--
-- Until now the mobile app ignored is_verified. Now an unverified account
-- waits for approval, so these older rows would be locked out.
-- ===========================================================================

-- 1. See who is affected first.
select lower(coalesce(role, '<none>')) as role,
       public.is_student_email(email)  as student_format,
       count(*)
from public.user_profiles
where is_verified is not true
  and is_active is not false
group by 1, 2
order by 1, 2;

-- 2. Students in the student format, mostly from the removed email sign-up.
--    The admin app's pending list leaves these out, so nothing else can
--    approve them.
update public.user_profiles
set is_verified = true
where lower(role) = 'student'
  and is_verified is not true
  and is_active is not false
  and public.is_student_email(email);

-- Everyone else who is unverified appears in Users > Pending Approval.
