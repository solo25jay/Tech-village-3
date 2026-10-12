-- LMS core and invitation tests (pgTAP). Run with:  supabase test db   (fresh local database)
--
-- Cast
--   alice  owner of Alice Academy (institution plan)      bob   owner of Bob Co (starter plan)
--   carol  instructor in Alice Academy                     dave  student in Alice Academy
--   erin   learner in the official LMS only                gus   student in Bob Co
--   pat    owner of the official LMS
--   ivy, dup, quin, ned, zed, mallory: people who receive (or try to abuse) invitations

begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

create or replace function pg_temp.act_as(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
end $$;
create or replace function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
end $$;

-- ---------- fixtures ----------
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('a1111111-1111-1111-1111-111111111111', 'alice@test.dev',  now(), '{"full_name":"Alice","signup_intent":"workspace"}'),
  ('b2222222-2222-2222-2222-222222222222', 'bob@test.dev',    now(), '{"full_name":"Bob","signup_intent":"workspace"}'),
  ('c3333333-3333-3333-3333-333333333333', 'carol@test.dev',  now(), '{"full_name":"Carol"}'),
  ('d4444444-4444-4444-4444-444444444444', 'dave@test.dev',   now(), '{"full_name":"Dave"}'),
  ('e5555555-5555-5555-5555-555555555555', 'erin@test.dev',   now(), '{"full_name":"Erin","signup_intent":"learner"}'),
  ('99999999-9999-9999-9999-999999999999', 'pat@test.dev',    now(), '{"full_name":"Pat"}'),
  ('91919191-9191-9191-9191-919191919191', 'gus@test.dev',    now(), '{"full_name":"Gus"}'),
  ('11111111-1111-1111-1111-111111111111', 'ivy@test.dev',    now(), '{"full_name":"Ivy"}'),
  ('66666666-6666-6666-6666-666666666666', 'dup@test.dev',    now(), '{"full_name":"Dup"}'),
  ('44444444-4444-4444-4444-444444444444', 'quin@test.dev',   now(), '{"full_name":"Quin"}'),
  ('55555555-5555-5555-5555-555555555555', 'ned@test.dev',    now(), '{"full_name":"Ned"}'),
  ('33333333-3333-3333-3333-333333333333', 'zed@test.dev',    null,  '{"full_name":"Zed"}'),
  ('22222222-2222-2222-2222-222222222222', 'mallory@test.dev',now(), '{"full_name":"Mallory"}');

do $$ begin perform set_config('tv.official', (select id::text from public.organisations where is_platform_tenant), false); end $$;
insert into public.memberships (org_id, user_id, role_id)
  values (current_setting('tv.official')::uuid, '99999999-9999-9999-9999-999999999999', public.owner_role_id());

select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
do $$ begin perform set_config('tv.org_a', public.create_workspace('Alice Academy','Alice Academy','alice-academy','training_academy','institution')::text, false); end $$;
reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
do $$ begin perform set_config('tv.org_b', public.create_workspace('Bob Co','Bob Co','bob-co','corporate_training','starter')::text, false); end $$;

reset role;
insert into public.memberships (org_id, user_id, role_id) values
  (current_setting('tv.org_a')::uuid, 'c3333333-3333-3333-3333-333333333333', public.system_role_id('instructor')),
  (current_setting('tv.org_a')::uuid, 'd4444444-4444-4444-4444-444444444444', public.system_role_id('student')),
  (current_setting('tv.org_b')::uuid, '91919191-9191-9191-9191-919191919191', public.system_role_id('student'));

-- =====================================================================
-- 1. Creating courses
-- =====================================================================
select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
do $$ declare v uuid; begin
  insert into public.courses (org_id, title, summary) values (current_setting('tv.org_a')::uuid, 'Python 101', 'Start here') returning id into v;
  perform set_config('tv.course_a', v::text, false);
end $$;
select is((select status::text from public.courses where id = current_setting('tv.course_a')::uuid), 'draft', 'new courses always start as drafts');

reset role; select pg_temp.act_as('c3333333-3333-3333-3333-333333333333');
do $$ declare v uuid; begin
  insert into public.courses (org_id, title) values (current_setting('tv.org_a')::uuid, 'Carol Draft') returning id into v;
  perform set_config('tv.course_c', v::text, false);
end $$;
select ok(true, 'an instructor can create a course');

reset role; select pg_temp.act_as('d4444444-4444-4444-4444-444444444444');
select throws_ok(format($q$insert into public.courses (org_id, title) values (%L, 'Student Course')$q$, current_setting('tv.org_a')), '42501', null, 'a student cannot create a course');

reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select throws_ok(format($q$insert into public.courses (org_id, title) values (%L, 'Intruder')$q$, current_setting('tv.org_a')), '42501', null, 'bob cannot create a course in alice''s workspace');

reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select throws_ok(format($q$insert into public.courses (org_id, title, status) values (%L, 'Sneaky', 'published')$q$, current_setting('tv.org_a')), '42501', null, 'status cannot be set at insert time (column grant)');
select throws_ok(format($q$update public.courses set org_id = %L where id = %L$q$, current_setting('tv.org_b'), current_setting('tv.course_a')), '42501', null, 'a course cannot be moved to another workspace (column grant)');
select throws_ok(format($q$update public.courses set created_by = 'b2222222-2222-2222-2222-222222222222' where id = %L$q$, current_setting('tv.course_a')), '42501', null, 'course authorship cannot be changed (column grant)');

-- =====================================================================
-- 2. Who can see which courses
-- =====================================================================
select is((select count(*) from public.courses), 2::bigint, 'alice (courses.manage) sees every course in her workspace, drafts included');
reset role; select pg_temp.act_as('c3333333-3333-3333-3333-333333333333');
select is((select title from public.courses), 'Carol Draft', 'an instructor sees only their own drafts');
reset role; select pg_temp.act_as('d4444444-4444-4444-4444-444444444444');
select is((select count(*) from public.courses), 0::bigint, 'a student sees no drafts');
reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select is((select count(*) from public.courses), 0::bigint, 'bob sees none of alice''s courses');

reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select lives_ok(format($q$update public.courses set status = 'published' where id = %L$q$, current_setting('tv.course_a')), 'the owner can publish a course');

reset role; select pg_temp.act_as('d4444444-4444-4444-4444-444444444444');
select is((select title from public.courses), 'Python 101', 'a student sees the published course but not the draft');
select lives_ok(format($q$update public.courses set title = 'Student Edit' where id = %L$q$, current_setting('tv.course_a')), 'a student''s edit is silently filtered');
reset role;
select is((select title from public.courses where id = current_setting('tv.course_a')::uuid), 'Python 101', 'the course is unchanged after the student''s attempt');

select pg_temp.act_as('c3333333-3333-3333-3333-333333333333');
select lives_ok(format($q$update public.courses set title = 'Carol Edit' where id = %L$q$, current_setting('tv.course_a')), 'an instructor''s edit of someone else''s course is silently filtered');
select lives_ok(format($q$update public.courses set summary = 'Mine' where id = %L$q$, current_setting('tv.course_c')), 'an instructor can edit their own course');
reset role;
select is((select title from public.courses where id = current_setting('tv.course_a')::uuid), 'Python 101', 'the other instructor''s course is unchanged');

reset role; select pg_temp.act_as_anon();
select throws_ok($q$select count(*) from public.courses$q$, '42501', null, 'visitors cannot read courses');

-- =====================================================================
-- 3. Lesson content: mixed text and video, tenant-safe keys, constraints
-- =====================================================================
reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
do $$ declare m uuid; l uuid; begin
  insert into public.modules (org_id, course_id, title, position) values (current_setting('tv.org_a')::uuid, current_setting('tv.course_a')::uuid, 'Basics', 0) returning id into m;
  insert into public.lessons (org_id, course_id, module_id, title, position) values (current_setting('tv.org_a')::uuid, current_setting('tv.course_a')::uuid, m, 'Hello world', 0) returning id into l;
  perform set_config('tv.module_a', m::text, false);
  perform set_config('tv.lesson_a', l::text, false);
end $$;
select lives_ok(format($q$insert into public.lesson_blocks (org_id, course_id, lesson_id, block_type, body, position) values (%L, %L, %L, 'text', 'Read this first.', 0)$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.lesson_a')), 'a lesson can contain a text block');
select lives_ok(format($q$insert into public.lesson_blocks (org_id, course_id, lesson_id, block_type, video_url, position) values (%L, %L, %L, 'video', 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', 1)$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.lesson_a')), '...and a YouTube video block in the same lesson');
select lives_ok(format($q$insert into public.lesson_blocks (org_id, course_id, lesson_id, block_type, video_url, position) values (%L, %L, %L, 'video', 'https://vimeo.com/123456789', 2)$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.lesson_a')), '...and a Vimeo video block');
select is((select count(*) from public.lesson_blocks where lesson_id = current_setting('tv.lesson_a')::uuid), 3::bigint, 'text and video blocks are stored together in one lesson');

select throws_ok(format($q$insert into public.lesson_blocks (org_id, course_id, lesson_id, block_type, video_url) values (%L, %L, %L, 'video', 'https://evil.example/watch?v=abcdefghijk')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.lesson_a')), '23514', null, 'video links from unknown hosts are rejected');
select throws_ok(format($q$insert into public.lesson_blocks (org_id, course_id, lesson_id, block_type, video_url) values (%L, %L, %L, 'video', 'javascript:alert(1)')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.lesson_a')), '23514', null, 'script URLs are rejected');
select throws_ok(format($q$insert into public.lesson_blocks (org_id, course_id, lesson_id, block_type, video_url) values (%L, %L, %L, 'video', 'https://www.youtube.com/watch?v=dQw4w9WgXcQ&autoplay=1')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.lesson_a')), '23514', null, 'only canonical video URLs are stored');
select throws_ok(format($q$insert into public.lesson_blocks (org_id, course_id, lesson_id, block_type, body) values (%L, %L, %L, 'text', '')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.lesson_a')), '23514', null, 'empty text blocks are rejected');
select throws_ok(format($q$insert into public.lesson_blocks (org_id, course_id, lesson_id, block_type, body, video_url) values (%L, %L, %L, 'text', 'x', 'https://vimeo.com/123456789')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.lesson_a')), '23514', null, 'a block cannot be both text and video');

-- composite keys: the database refuses cross-tenant and cross-course links
select throws_ok(format($q$insert into public.modules (org_id, course_id, title) values (%L, %L, 'Lying about the tenant')$q$, current_setting('tv.org_b'), current_setting('tv.course_a')), '23503', null, 'a module cannot claim a different workspace than its course');
do $$ declare m uuid; begin
  insert into public.modules (org_id, course_id, title) values (current_setting('tv.org_a')::uuid, current_setting('tv.course_c')::uuid, 'Carol module') returning id into m;
  perform set_config('tv.module_c', m::text, false);
end $$;
select throws_ok(format($q$insert into public.lessons (org_id, course_id, module_id, title) values (%L, %L, %L, 'Wrong module')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.module_c')), '23503', null, 'a lesson cannot sit in another course''s module');

reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select throws_ok(format($q$insert into public.modules (org_id, course_id, title) values (%L, %L, 'Bob into Alice')$q$, current_setting('tv.org_b'), current_setting('tv.course_a')), '42501', null, 'bob cannot add modules to alice''s course');
select is((select count(*) from public.lesson_blocks), 0::bigint, 'bob cannot read alice''s lesson content');

reset role; select pg_temp.act_as('c3333333-3333-3333-3333-333333333333');
select throws_ok(format($q$insert into public.modules (org_id, course_id, title) values (%L, %L, 'Carol into Alice')$q$, current_setting('tv.org_a'), current_setting('tv.course_a')), '42501', null, 'an instructor cannot edit content of a course they do not own');

-- =====================================================================
-- 4. Enrolment gates the content
-- =====================================================================
reset role; select pg_temp.act_as('d4444444-4444-4444-4444-444444444444');
select is((select count(*) from public.lessons), 0::bigint, 'an unenrolled student cannot read lessons of a published course');
select is((select count(*) from public.lesson_blocks), 0::bigint, '...or lesson blocks');
select throws_ok(format($q$insert into public.enrolments (org_id, course_id, user_id) values (%L, %L, 'd4444444-4444-4444-4444-444444444444')$q$, current_setting('tv.org_a'), current_setting('tv.course_c')), '42501', null, 'a student cannot enrol in an unpublished course');
select throws_ok(format($q$insert into public.enrolments (org_id, course_id, user_id) values (%L, %L, 'e5555555-5555-5555-5555-555555555555')$q$, current_setting('tv.org_a'), current_setting('tv.course_a')), '42501', null, 'a student cannot enrol someone else');
select lives_ok(format($q$insert into public.enrolments (org_id, course_id, user_id) values (%L, %L, 'd4444444-4444-4444-4444-444444444444')$q$, current_setting('tv.org_a'), current_setting('tv.course_a')), 'a student can enrol themselves in a published course');
select is((select count(*) from public.lessons), 1::bigint, 'once enrolled the student can read the lessons');
select is((select count(*) from public.lesson_blocks), 3::bigint, '...and every block');
select throws_ok(format($q$insert into public.enrolments (org_id, course_id, user_id) values (%L, %L, 'd4444444-4444-4444-4444-444444444444')$q$, current_setting('tv.org_a'), current_setting('tv.course_a')), '23505', null, 'double enrolment is rejected');
select throws_ok($q$update public.enrolments set user_id = 'e5555555-5555-5555-5555-555555555555'$q$, '42501', null, 'an enrolment cannot be re-pointed at another user (column grant)');

reset role; select pg_temp.act_as('e5555555-5555-5555-5555-555555555555');
select throws_ok(format($q$insert into public.enrolments (org_id, course_id, user_id) values (%L, %L, 'e5555555-5555-5555-5555-555555555555')$q$, current_setting('tv.org_a'), current_setting('tv.course_a')), '42501', null, 'a learner of the official LMS cannot enrol in a customer workspace course');
select is((select count(*) from public.courses), 0::bigint, '...and cannot even see it');

reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select lives_ok(format($q$insert into public.enrolments (org_id, course_id, user_id) values (%L, %L, 'c3333333-3333-3333-3333-333333333333')$q$, current_setting('tv.org_a'), current_setting('tv.course_a')), 'staff can enrol a member of the workspace');
select throws_ok(format($q$insert into public.enrolments (org_id, course_id, user_id) values (%L, %L, 'e5555555-5555-5555-5555-555555555555')$q$, current_setting('tv.org_a'), current_setting('tv.course_a')), '42501', null, 'staff cannot enrol someone who is not a member');
select is((select count(*) from public.enrolments), 2::bigint, 'staff see the enrolments of their own workspace');

reset role; select pg_temp.act_as('d4444444-4444-4444-4444-444444444444');
select is((select count(*) from public.enrolments), 1::bigint, 'a student sees only their own enrolment');
reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select is((select count(*) from public.enrolments), 0::bigint, 'bob sees none of alice''s enrolments');

-- =====================================================================
-- 5. Progress
-- =====================================================================
reset role; select pg_temp.act_as('d4444444-4444-4444-4444-444444444444');
select lives_ok(format($q$insert into public.lesson_progress (org_id, course_id, lesson_id, user_id) values (%L, %L, %L, 'd4444444-4444-4444-4444-444444444444')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.lesson_a')), 'a student can mark a lesson complete');
select throws_ok(format($q$insert into public.lesson_progress (org_id, course_id, lesson_id, user_id) values (%L, %L, %L, 'd4444444-4444-4444-4444-444444444444')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.lesson_a')), '23505', null, 'completing twice is rejected (the app treats it as done)');
select throws_ok(format($q$insert into public.lesson_progress (org_id, course_id, lesson_id, user_id) values (%L, %L, %L, 'e5555555-5555-5555-5555-555555555555')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.lesson_a')), '42501', null, 'nobody can record progress on behalf of another user');

reset role; select pg_temp.act_as('e5555555-5555-5555-5555-555555555555');
select throws_ok(format($q$insert into public.lesson_progress (org_id, course_id, lesson_id, user_id) values (%L, %L, %L, 'e5555555-5555-5555-5555-555555555555')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.lesson_a')), '42501', null, 'progress needs an enrolment');

reset role; select pg_temp.act_as('c3333333-3333-3333-3333-333333333333');
select is((select count(*) from public.lesson_progress), 0::bigint, 'an instructor without reports.view cannot read learner progress');
reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select is((select count(*) from public.lesson_progress), 1::bigint, 'the owner can read progress in their own workspace');
reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select is((select count(*) from public.lesson_progress), 0::bigint, 'bob cannot read alice''s learner progress');

-- unpublishing or withdrawing closes the door
reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select lives_ok(format($q$update public.courses set status = 'draft' where id = %L$q$, current_setting('tv.course_a')), 'a course can be unpublished');
reset role; select pg_temp.act_as('d4444444-4444-4444-4444-444444444444');
select is((select count(*) from public.lessons), 0::bigint, 'an unpublished course hides its content from enrolled students');
reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select lives_ok(format($q$update public.courses set status = 'published' where id = %L$q$, current_setting('tv.course_a')), 'and can be published again');
reset role; select pg_temp.act_as('d4444444-4444-4444-4444-444444444444');
select lives_ok($q$update public.enrolments set status = 'withdrawn'$q$, 'a student can withdraw');
select is((select count(*) from public.lessons), 0::bigint, 'a withdrawn student loses access to the content');

-- =====================================================================
-- 6. Plan limits are enforced by the database
-- =====================================================================
reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
do $$ declare v uuid; begin
  insert into public.courses (org_id, title) values (current_setting('tv.org_b')::uuid, 'B One') returning id into v;
  perform set_config('tv.course_b1', v::text, false);
  insert into public.courses (org_id, title) values (current_setting('tv.org_b')::uuid, 'B Two') returning id into v;
  perform set_config('tv.course_b2', v::text, false);
  insert into public.courses (org_id, title) values (current_setting('tv.org_b')::uuid, 'B Three');
end $$;
select throws_ok(format($q$insert into public.courses (org_id, title) values (%L, 'B Four')$q$, current_setting('tv.org_b')), 'P0001', 'Your plan allows 3 course(s). Upgrade to add more.', 'the starter plan limits courses to three');

reset role; select pg_temp.act_as('99999999-9999-9999-9999-999999999999');
select lives_ok(format($q$insert into public.courses (org_id, title) values (%L, 'Official Course')$q$, current_setting('tv.official')), 'the official LMS owner can create courses');

-- shrink the starter learner limit to prove enforcement without creating 25 users
reset role;
update public.plan_entitlements set value = '{"limit": 1}' where key = 'max_students' and plan_id = (select id from public.plans where key = 'starter');
select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select lives_ok(format($q$update public.courses set status = 'published' where id in (%L, %L)$q$, current_setting('tv.course_b1'), current_setting('tv.course_b2')), 'bob publishes two courses');
select lives_ok(format($q$insert into public.enrolments (org_id, course_id, user_id) values (%L, %L, 'b2222222-2222-2222-2222-222222222222')$q$, current_setting('tv.org_b'), current_setting('tv.course_b1')), 'the first learner fits the limit');
select lives_ok(format($q$insert into public.enrolments (org_id, course_id, user_id) values (%L, %L, 'b2222222-2222-2222-2222-222222222222')$q$, current_setting('tv.org_b'), current_setting('tv.course_b2')), 'the same learner in a second course is not counted twice');
reset role; select pg_temp.act_as('91919191-9191-9191-9191-919191919191');
select throws_ok(format($q$insert into public.enrolments (org_id, course_id, user_id) values (%L, %L, '91919191-9191-9191-9191-919191919191')$q$, current_setting('tv.org_b'), current_setting('tv.course_b1')), 'P0001', 'Your plan allows 1 learner(s). Upgrade to enrol more.', 'a second learner is refused once the plan limit is reached');

-- =====================================================================
-- 7. Invitations
-- =====================================================================
reset role; select pg_temp.act_as('c3333333-3333-3333-3333-333333333333');
select throws_ok(format($q$select public.create_invitation(%L, 'x@test.dev', 'student')$q$, current_setting('tv.org_a')), '42501', null, 'an instructor cannot invite people');

reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select throws_ok(format($q$select public.create_invitation(%L, 'x@test.dev', 'student')$q$, current_setting('tv.org_a')), '42501', null, 'bob cannot invite people into alice''s workspace');

reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select throws_ok(format($q$select public.create_invitation(%L, 'x@test.dev', 'owner')$q$, current_setting('tv.org_a')), 'P0001', 'Owners cannot be invited', 'owners cannot be created through invitations');
select throws_ok(format($q$select public.create_invitation(%L, 'x@test.dev', 'wizard')$q$, current_setting('tv.org_a')), 'P0001', 'Unknown role', 'an unknown role is rejected');
select throws_ok(format($q$select public.create_invitation(%L, 'not-an-email', 'student')$q$, current_setting('tv.org_a')), 'P0001', 'Enter a valid email address', 'an invalid email is rejected');
select throws_ok(format($q$select public.create_invitation(%L, 'Dave@Test.dev', 'student')$q$, current_setting('tv.org_a')), 'P0001', 'That person is already a member', 'inviting an existing member is rejected (case-insensitive)');
select throws_ok($q$insert into public.invitations (org_id, email, role_id, token_hash) values (gen_random_uuid(), 'a@b.co', public.owner_role_id(), 'x')$q$, '42501', null, 'invitations cannot be written directly');

do $$ begin
  perform set_config('tv.tok_ivy',   public.create_invitation(current_setting('tv.org_a')::uuid, 'Ivy@Test.dev', 'instructor'), false);
  perform set_config('tv.tok_victim',public.create_invitation(current_setting('tv.org_a')::uuid, 'victim@test.dev', 'student'), false);
  perform set_config('tv.tok_zed',   public.create_invitation(current_setting('tv.org_a')::uuid, 'zed@test.dev', 'student'), false);
  perform set_config('tv.tok_quin',  public.create_invitation(current_setting('tv.org_a')::uuid, 'quin@test.dev', 'student'), false);
  perform set_config('tv.tok_ned',   public.create_invitation(current_setting('tv.org_a')::uuid, 'ned@test.dev', 'student'), false);
  perform set_config('tv.tok_dup_a', public.create_invitation(current_setting('tv.org_a')::uuid, 'dup@test.dev', 'student'), false);
  perform set_config('tv.tok_dup_b', public.create_invitation(current_setting('tv.org_a')::uuid, 'dup@test.dev', 'student'), false);
end $$;
select is((select count(*) from public.invitations where status = 'pending'), 6::bigint, 'the owner sees pending invitations (re-inviting replaced the earlier one)');
select is((select count(*) from public.invitations where status = 'revoked'), 1::bigint, 're-inviting the same email revoked the first link');

reset role;
select is((select count(*) from public.invitations where token_hash = current_setting('tv.tok_ivy')), 0::bigint, 'the raw token is never stored');
select is((select count(*) from public.invitations where token_hash = encode(sha256(convert_to(current_setting('tv.tok_ivy'), 'utf8')), 'hex')), 1::bigint, 'only its SHA-256 hash is stored');
select is((select email from public.invitations where token_hash = encode(sha256(convert_to(current_setting('tv.tok_ivy'), 'utf8')), 'hex')), 'ivy@test.dev', 'invited emails are normalised to lower case');

select pg_temp.act_as('c3333333-3333-3333-3333-333333333333');
select is((select count(*) from public.invitations), 0::bigint, 'an instructor cannot read invitations');
reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select is((select count(*) from public.invitations), 0::bigint, 'bob cannot read alice''s invitations');

-- preview and accept
reset role; select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is((select workspace_name from public.invitation_preview(current_setting('tv.tok_ivy'))), 'Alice Academy', 'the link holder can preview the workspace');
select is((select count(*) from public.invitation_preview('not-a-real-token')), 0::bigint, 'an unknown token reveals nothing');
select lives_ok(format($q$select public.accept_invitation(%L)$q$, current_setting('tv.tok_ivy')), 'the invited person accepts with a verified matching email');
select is((select count(*) from public.memberships where org_id = current_setting('tv.org_a')::uuid and user_id = '11111111-1111-1111-1111-111111111111'), 1::bigint, 'accepting creates the membership');
select is((select r.key from public.memberships m join public.roles r on r.id = m.role_id where m.user_id = '11111111-1111-1111-1111-111111111111' and m.org_id = current_setting('tv.org_a')::uuid), 'instructor', 'with exactly the invited role');
select throws_ok(format($q$select public.accept_invitation(%L)$q$, current_setting('tv.tok_ivy')), 'P0001', 'This invitation is no longer valid', 'a link works only once');

reset role; select pg_temp.act_as('22222222-2222-2222-2222-222222222222');
select throws_ok(format($q$select public.accept_invitation(%L)$q$, current_setting('tv.tok_victim')), '42501', 'This invitation was sent to a different email address', 'someone else cannot use a leaked link');
reset role; select pg_temp.act_as('33333333-3333-3333-3333-333333333333');
select throws_ok(format($q$select public.accept_invitation(%L)$q$, current_setting('tv.tok_zed')), '42501', null, 'an unverified email cannot accept, even if it matches');

reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select lives_ok(format($q$select public.revoke_invitation(id) from public.invitations where token_hash = encode(sha256(convert_to(%L, 'utf8')), 'hex')$q$, current_setting('tv.tok_quin')), 'the owner can revoke an invitation');
reset role; select pg_temp.act_as('44444444-4444-4444-4444-444444444444');
select throws_ok(format($q$select public.accept_invitation(%L)$q$, current_setting('tv.tok_quin')), 'P0001', 'This invitation is no longer valid', 'a revoked link no longer works');

reset role;
do $$ begin
  perform set_config('tv.inv_ned', (select id::text from public.invitations where token_hash = encode(sha256(convert_to(current_setting('tv.tok_ned'), 'utf8')), 'hex')), false);
end $$;
select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select throws_ok(format($q$select public.revoke_invitation(%L::uuid)$q$, current_setting('tv.inv_ned')), '42501', null, 'bob cannot revoke alice''s invitation even if he knows its ID');

reset role;
update public.organisations set status = 'suspended' where id = current_setting('tv.org_a')::uuid;
select pg_temp.act_as('55555555-5555-5555-5555-555555555555');
select throws_ok(format($q$select public.accept_invitation(%L)$q$, current_setting('tv.tok_ned')), 'P0001', 'This workspace is not available', 'an invitation cannot be accepted into a suspended workspace');
reset role;
update public.organisations set status = 'active' where id = current_setting('tv.org_a')::uuid;

update public.invitations set expires_at = now() - interval '1 day' where token_hash = encode(sha256(convert_to(current_setting('tv.tok_ned'), 'utf8')), 'hex');
select pg_temp.act_as('55555555-5555-5555-5555-555555555555');
select throws_ok(format($q$select public.accept_invitation(%L)$q$, current_setting('tv.tok_ned')), 'P0001', 'This invitation has expired. Ask for a new one.', 'an expired link is refused');

reset role; select pg_temp.act_as('66666666-6666-6666-6666-666666666666');
select throws_ok(format($q$select public.accept_invitation(%L)$q$, current_setting('tv.tok_dup_a')), 'P0001', 'This invitation is no longer valid', 'the replaced link no longer works');
select lives_ok(format($q$select public.accept_invitation(%L)$q$, current_setting('tv.tok_dup_b')), '...and the newest link does');

-- members list
reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select is((select count(*) from public.list_members(current_setting('tv.org_a')::uuid)), 5::bigint, 'the owner lists all five members of the workspace');
select ok((select bool_or(email = 'dave@test.dev') from public.list_members(current_setting('tv.org_a')::uuid)), 'the list includes member emails for people who manage members');
select is((select count(*) from public.list_members(current_setting('tv.org_b')::uuid)), 0::bigint, 'the owner cannot list another workspace''s members');
reset role; select pg_temp.act_as('c3333333-3333-3333-3333-333333333333');
select is((select count(*) from public.list_members(current_setting('tv.org_a')::uuid)), 0::bigint, 'an instructor cannot list members');

reset role; select pg_temp.act_as_anon();
select throws_ok(format($q$select public.create_invitation(%L, 'a@b.co', 'student')$q$, current_setting('tv.org_a')), '42501', null, 'visitors cannot create invitations');
select throws_ok($q$select public.accept_invitation('x')$q$, '42501', null, 'visitors cannot accept invitations');
select throws_ok($q$select * from public.invitation_preview('x')$q$, '42501', null, 'visitors cannot preview invitations');

select * from finish();
rollback;
