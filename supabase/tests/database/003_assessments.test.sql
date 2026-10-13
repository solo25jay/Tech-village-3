-- Assessment tests (pgTAP). Run with:  supabase test db   (fresh local database)
--
-- Cast
--   alice  owner of Alice Academy (institution)      bob   owner of Bob Co (starter)
--   carol  instructor in Alice Academy (not the author of Alice's course)
--   dave, hana, ivy  students enrolled in Alice's course      frank  student NOT enrolled

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
  ('a1111111-1111-1111-1111-111111111111', 'alice@test.dev', now(), '{"full_name":"Alice","signup_intent":"workspace"}'),
  ('b2222222-2222-2222-2222-222222222222', 'bob@test.dev',   now(), '{"full_name":"Bob","signup_intent":"workspace"}'),
  ('c3333333-3333-3333-3333-333333333333', 'carol@test.dev', now(), '{"full_name":"Carol"}'),
  ('d4444444-4444-4444-4444-444444444444', 'dave@test.dev',  now(), '{"full_name":"Dave"}'),
  ('84848484-8484-8484-8484-848484848484', 'hana@test.dev',  now(), '{"full_name":"Hana"}'),
  ('11111111-1111-1111-1111-111111111111', 'ivy@test.dev',   now(), '{"full_name":"Ivy"}'),
  ('f6666666-6666-6666-6666-666666666666', 'frank@test.dev', now(), '{"full_name":"Frank"}');

select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
do $$ begin perform set_config('tv.org_a', public.create_workspace('Alice Academy','Alice Academy','alice-academy','training_academy','institution')::text, false); end $$;
reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
do $$ begin perform set_config('tv.org_b', public.create_workspace('Bob Co','Bob Co','bob-co','corporate_training','starter')::text, false); end $$;

reset role;
insert into public.memberships (org_id, user_id, role_id)
select current_setting('tv.org_a')::uuid, u.id, public.system_role_id(u.role)
from (values ('c3333333-3333-3333-3333-333333333333'::uuid, 'instructor'), ('d4444444-4444-4444-4444-444444444444'::uuid, 'student'),
             ('84848484-8484-8484-8484-848484848484'::uuid, 'student'), ('11111111-1111-1111-1111-111111111111'::uuid, 'student'),
             ('f6666666-6666-6666-6666-666666666666'::uuid, 'student')) as u(id, role);

-- Alice's published course, with three enrolled students
select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
do $$ declare c uuid; begin
  insert into public.courses (org_id, title) values (current_setting('tv.org_a')::uuid, 'Course A') returning id into c;
  update public.courses set status = 'published' where id = c;
  perform set_config('tv.course_a', c::text, false);
end $$;
reset role;
insert into public.enrolments (org_id, course_id, user_id)
select current_setting('tv.org_a')::uuid, current_setting('tv.course_a')::uuid, u
from unnest(array['d4444444-4444-4444-4444-444444444444','84848484-8484-8484-8484-848484848484','11111111-1111-1111-1111-111111111111']::uuid[]) u;

-- Bob's own course and draft quiz (for cross-tenant attempts)
select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
do $$ declare c uuid; a uuid; begin
  insert into public.courses (org_id, title) values (current_setting('tv.org_b')::uuid, 'Bob Course') returning id into c;
  insert into public.assessments (org_id, course_id, kind, title) values (current_setting('tv.org_b')::uuid, c, 'quiz', 'Bob Quiz') returning id into a;
  perform set_config('tv.course_b', c::text, false);
  perform set_config('tv.quiz_b', a::text, false);
end $$;

-- =====================================================================
-- 1. A quiz cannot go live until it is complete
-- =====================================================================
reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
do $$ declare a uuid; begin
  insert into public.assessments (org_id, course_id, kind, title) values (current_setting('tv.org_a')::uuid, current_setting('tv.course_a')::uuid, 'quiz', 'Empty quiz') returning id into a;
  perform set_config('tv.quiz_e', a::text, false);
end $$;
select is((select status::text from public.assessments where id = current_setting('tv.quiz_e')::uuid), 'draft', 'new assessments always start as drafts');
select throws_ok(format($q$update public.assessments set status = 'published' where id = %L$q$, current_setting('tv.quiz_e')), 'P0001', 'Add at least one question before publishing', 'a quiz with no questions cannot be published');

do $$ declare qq uuid; o1 uuid; o2 uuid; begin
  insert into public.quiz_questions (org_id, course_id, assessment_id, prompt) values (current_setting('tv.org_a')::uuid, current_setting('tv.course_a')::uuid, current_setting('tv.quiz_e')::uuid, '2 + 2?') returning id into qq;
  insert into public.quiz_options (org_id, course_id, assessment_id, question_id, label) values (current_setting('tv.org_a')::uuid, current_setting('tv.course_a')::uuid, current_setting('tv.quiz_e')::uuid, qq, '3') returning id into o1;
  perform set_config('tv.qe', qq::text, false); perform set_config('tv.qe_o1', o1::text, false);
end $$;
select throws_ok(format($q$update public.assessments set status = 'published' where id = %L$q$, current_setting('tv.quiz_e')), 'P0001', 'Every question needs at least two options and one correct answer', 'a question with one option cannot be published');
do $$ declare o2 uuid; begin
  insert into public.quiz_options (org_id, course_id, assessment_id, question_id, label) values (current_setting('tv.org_a')::uuid, current_setting('tv.course_a')::uuid, current_setting('tv.quiz_e')::uuid, current_setting('tv.qe')::uuid, '4') returning id into o2;
  perform set_config('tv.qe_o2', o2::text, false);
end $$;
select throws_ok(format($q$update public.assessments set status = 'published' where id = %L$q$, current_setting('tv.quiz_e')), 'P0001', 'Every question needs at least two options and one correct answer', 'a question with no answer key cannot be published');
select lives_ok(format($q$insert into public.quiz_answer_keys (org_id, course_id, assessment_id, question_id, option_id) values (%L, %L, %L, %L, %L)$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.quiz_e'), current_setting('tv.qe'), current_setting('tv.qe_o2')), 'an answer key can be set');
select lives_ok(format($q$update public.assessments set status = 'published' where id = %L$q$, current_setting('tv.quiz_e')), 'a complete quiz can be published');
select throws_ok(format($q$insert into public.quiz_questions (org_id, course_id, assessment_id, prompt) values (%L, %L, %L, 'Sneaky extra')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.quiz_e')), 'P0001', 'Unpublish the quiz before changing its questions', 'questions are frozen while a quiz is published');
select throws_ok(format($q$update public.quiz_options set label = 'changed' where id = %L$q$, current_setting('tv.qe_o1')), 'P0001', 'Unpublish the quiz before changing its questions', 'options are frozen while published');
select throws_ok(format($q$delete from public.quiz_answer_keys where question_id = %L$q$, current_setting('tv.qe')), 'P0001', 'Unpublish the quiz before changing its questions', 'the answer key is frozen while published');
select lives_ok(format($q$update public.assessments set status = 'draft' where id = %L$q$, current_setting('tv.quiz_e')), 'a quiz can be unpublished');
select lives_ok(format($q$update public.quiz_options set label = 'four' where id = %L$q$, current_setting('tv.qe_o2')), '...and then edited');

-- ---------- the main quiz (pass mark 50, two attempts) ----------
do $$ declare qz uuid; q1 uuid; q2 uuid; a uuid; b uuid; c uuid; d uuid; e uuid; f uuid;
  oa uuid := current_setting('tv.org_a')::uuid; ca uuid := current_setting('tv.course_a')::uuid;
begin
  insert into public.assessments (org_id, course_id, kind, title, pass_mark, max_attempts) values (oa, ca, 'quiz', 'Quiz 1', 50, 2) returning id into qz;
  insert into public.quiz_questions (org_id, course_id, assessment_id, prompt, position) values (oa, ca, qz, 'Question one', 0) returning id into q1;
  insert into public.quiz_questions (org_id, course_id, assessment_id, prompt, position) values (oa, ca, qz, 'Question two', 1) returning id into q2;
  insert into public.quiz_options (org_id, course_id, assessment_id, question_id, label, position) values (oa, ca, qz, q1, 'wrong 1a', 0) returning id into a;
  insert into public.quiz_options (org_id, course_id, assessment_id, question_id, label, position) values (oa, ca, qz, q1, 'right 1', 1) returning id into b;
  insert into public.quiz_options (org_id, course_id, assessment_id, question_id, label, position) values (oa, ca, qz, q1, 'wrong 1b', 2);
  insert into public.quiz_options (org_id, course_id, assessment_id, question_id, label, position) values (oa, ca, qz, q2, 'wrong 2a', 0) returning id into c;
  insert into public.quiz_options (org_id, course_id, assessment_id, question_id, label, position) values (oa, ca, qz, q2, 'wrong 2b', 1);
  insert into public.quiz_options (org_id, course_id, assessment_id, question_id, label, position) values (oa, ca, qz, q2, 'right 2', 2) returning id into d;
  insert into public.quiz_answer_keys (org_id, course_id, assessment_id, question_id, option_id) values (oa, ca, qz, q1, b), (oa, ca, qz, q2, d);
  perform set_config('tv.quiz', qz::text, false);
  perform set_config('tv.q1', q1::text, false); perform set_config('tv.q2', q2::text, false);
  perform set_config('tv.q1_right', b::text, false); perform set_config('tv.q2_right', d::text, false);
  perform set_config('tv.ans_right', jsonb_build_object(q1::text, b::text, q2::text, d::text)::text, false);
  perform set_config('tv.ans_wrong', jsonb_build_object(q1::text, a::text, q2::text, c::text)::text, false);
  perform set_config('tv.ans_half',  jsonb_build_object(q1::text, b::text, q2::text, c::text)::text, false);
  perform set_config('tv.ans_cross', jsonb_build_object(q1::text, c::text, q2::text, a::text)::text, false);
end $$;
-- a second draft quiz for the answer-key integrity test
do $$ declare qz uuid; k1 uuid; k2 uuid; p uuid; oa uuid := current_setting('tv.org_a')::uuid; ca uuid := current_setting('tv.course_a')::uuid; begin
  insert into public.assessments (org_id, course_id, kind, title) values (oa, ca, 'quiz', 'Key test') returning id into qz;
  insert into public.quiz_questions (org_id, course_id, assessment_id, prompt) values (oa, ca, qz, 'k1') returning id into k1;
  insert into public.quiz_questions (org_id, course_id, assessment_id, prompt) values (oa, ca, qz, 'k2') returning id into k2;
  insert into public.quiz_options (org_id, course_id, assessment_id, question_id, label) values (oa, ca, qz, k2, 'belongs to k2') returning id into p;
  perform set_config('tv.kt', qz::text, false); perform set_config('tv.kt_q1', k1::text, false); perform set_config('tv.kt_opt_other', p::text, false);
end $$;
select lives_ok(format($q$update public.assessments set status = 'published' where id = %L$q$, current_setting('tv.quiz')), 'the main quiz is complete and publishes');

-- an assignment and a hidden draft
do $$ declare s uuid; h uuid; oa uuid := current_setting('tv.org_a')::uuid; ca uuid := current_setting('tv.course_a')::uuid; begin
  insert into public.assessments (org_id, course_id, kind, title, max_points) values (oa, ca, 'assignment', 'Essay', 10) returning id into s;
  update public.assessments set status = 'published' where id = s;
  insert into public.assessments (org_id, course_id, kind, title) values (oa, ca, 'assignment', 'Hidden draft') returning id into h;
  perform set_config('tv.essay', s::text, false); perform set_config('tv.draft', h::text, false);
end $$;
select is((select count(*) from public.assessments where course_id = current_setting('tv.course_a')::uuid), 5::bigint, 'the course editor sees all five assessments, drafts included');

-- =====================================================================
-- 2. What learners can and cannot read
-- =====================================================================
reset role; select pg_temp.act_as('d4444444-4444-4444-4444-444444444444');
select hasnt_column('public', 'quiz_options', 'is_correct', 'options carry no "correct" flag a learner could read');
select is((select count(*) from public.assessments), 2::bigint, 'an enrolled student sees only the two published assessments');
select is((select count(*) from public.quiz_questions), 2::bigint, '...and the published quiz''s questions');
select is((select count(*) from public.quiz_options), 6::bigint, '...and its options');
select is((select count(*) from public.quiz_answer_keys), 0::bigint, 'but never the answer key');
select throws_ok(format($q$insert into public.assessments (org_id, course_id, kind, title) values (%L, %L, 'quiz', 'Student quiz')$q$, current_setting('tv.org_a'), current_setting('tv.course_a')), '42501', null, 'a student cannot create assessments');

reset role; select pg_temp.act_as('f6666666-6666-6666-6666-666666666666');
select is((select count(*) from public.assessments), 0::bigint, 'a student who is not enrolled sees no assessments');
select is((select count(*) from public.quiz_options), 0::bigint, '...and no options');
select throws_ok(format($q$select public.submit_quiz(%L::uuid, '{}'::jsonb)$q$, current_setting('tv.quiz')), '42501', 'Enrol in the course to take this quiz', 'an unenrolled student cannot submit a quiz');

reset role; select pg_temp.act_as('c3333333-3333-3333-3333-333333333333');
select is((select count(*) from public.assessments where course_id = current_setting('tv.course_a')::uuid), 0::bigint, 'an instructor who does not own the course sees none of its assessments');

reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select is((select count(*) from public.assessments where course_id = current_setting('tv.course_a')::uuid), 0::bigint, 'bob sees none of alice''s assessments');
select throws_ok(format($q$insert into public.assessments (org_id, course_id, kind, title) values (%L, %L, 'quiz', 'Bob into Alice')$q$, current_setting('tv.org_b'), current_setting('tv.course_a')), '42501', null, 'bob cannot add assessments to alice''s course');

-- =====================================================================
-- 3. Server-side grading
-- =====================================================================
reset role; select pg_temp.act_as('d4444444-4444-4444-4444-444444444444');
select is(public.submit_quiz(current_setting('tv.quiz')::uuid, current_setting('tv.ans_wrong')::jsonb) ->> 'score_percent', '0', 'all wrong scores 0');
select is(public.submit_quiz(current_setting('tv.quiz')::uuid, current_setting('tv.ans_right')::jsonb) ->> 'score_percent', '100', 'all right scores 100');
select throws_ok(format($q$select public.submit_quiz(%L::uuid, %L::jsonb)$q$, current_setting('tv.quiz'), current_setting('tv.ans_right')), 'P0001', 'No attempts left', 'the attempt limit is enforced');
select is((select count(*) from public.quiz_attempts), 2::bigint, 'dave sees his two attempts');
select is((select passed::text from public.quiz_attempts where attempt_no = 2), 'true', 'the pass flag follows the pass mark');
select throws_ok(format($q$insert into public.quiz_attempts (org_id, course_id, assessment_id, user_id, attempt_no, score_percent, passed, answers) values (%L, %L, %L, 'd4444444-4444-4444-4444-444444444444', 9, 100, true, '{}')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.quiz')), '42501', null, 'a learner cannot forge an attempt');
select throws_ok($q$update public.quiz_attempts set score_percent = 100, passed = true$q$, '42501', null, 'a learner cannot edit a score');

reset role; select pg_temp.act_as('84848484-8484-8484-8484-848484848484');
select is(public.submit_quiz(current_setting('tv.quiz')::uuid, current_setting('tv.ans_half')::jsonb) ->> 'score_percent', '50', 'half right scores 50');
select is(public.submit_quiz(current_setting('tv.quiz')::uuid, current_setting('tv.ans_half')::jsonb) ->> 'passed', 'true', '50 meets a pass mark of 50');

reset role; select pg_temp.act_as('11111111-1111-1111-1111-111111111111');
select is(public.submit_quiz(current_setting('tv.quiz')::uuid, current_setting('tv.ans_cross')::jsonb) ->> 'score_percent', '0', 'options borrowed from another question score nothing');
select ok(position(current_setting('tv.q2_right') in public.submit_quiz(current_setting('tv.quiz')::uuid, '{"00000000-0000-0000-0000-000000000000":"x"}'::jsonb)::text) = 0,
          'the result never reveals a correct option id');
select throws_ok(format($q$select public.submit_quiz(%L::uuid, '[]'::jsonb)$q$, current_setting('tv.quiz')), 'P0001', 'Invalid answers', 'answers must be an object');

-- ---------- who can read attempts ----------
reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select is((select count(*) from public.quiz_attempts), 6::bigint, 'the course editor sees every learner''s attempts');
reset role; select pg_temp.act_as('d4444444-4444-4444-4444-444444444444');
select is((select count(*) from public.quiz_attempts), 2::bigint, 'a learner sees only their own attempts');
reset role; select pg_temp.act_as('c3333333-3333-3333-3333-333333333333');
select is((select count(*) from public.quiz_attempts), 0::bigint, 'an instructor who does not own the course sees no attempts');
reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select is((select count(*) from public.quiz_attempts), 0::bigint, 'bob sees none of alice''s attempts');

-- ---------- unpublished quizzes cannot be taken ----------
reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select lives_ok(format($q$update public.assessments set status = 'draft' where id = %L$q$, current_setting('tv.quiz')), 'alice unpublishes the quiz');
reset role; select pg_temp.act_as('84848484-8484-8484-8484-848484848484');
select throws_ok(format($q$select public.submit_quiz(%L::uuid, %L::jsonb)$q$, current_setting('tv.quiz'), current_setting('tv.ans_right')), 'P0001', 'Quiz not available', 'an unpublished quiz cannot be taken');
select is((select count(*) from public.assessments), 1::bigint, 'and it disappears for learners');
reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select lives_ok(format($q$update public.assessments set status = 'published' where id = %L$q$, current_setting('tv.quiz')), 'and can be published again');

-- =====================================================================
-- 4. Integrity: composite keys and the answer key
-- =====================================================================
select throws_ok(format($q$insert into public.quiz_questions (org_id, course_id, assessment_id, prompt) values (%L, %L, %L, 'Into Bob quiz')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.quiz_b')), '23503', null, 'a question cannot be attached to another workspace''s quiz');
select throws_ok(format($q$insert into public.quiz_answer_keys (org_id, course_id, assessment_id, question_id, option_id) values (%L, %L, %L, %L, %L)$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.kt'), current_setting('tv.kt_q1'), current_setting('tv.kt_opt_other')), '23503', null, 'an answer key cannot point at another question''s option');
select throws_ok(format($q$update public.assessments set kind = 'assignment' where id = %L$q$, current_setting('tv.quiz')), '42501', null, 'the kind of an assessment cannot change (column grant)');
select throws_ok(format($q$insert into public.assessments (org_id, course_id, kind, title, status) values (%L, %L, 'quiz', 'Sneaky', 'published')$q$, current_setting('tv.org_a'), current_setting('tv.course_a')), '42501', null, 'assessments cannot be created already published (column grant)');
select throws_ok(format($q$insert into public.assessments (org_id, course_id, kind, title, pass_mark) values (%L, %L, 'quiz', 'Bad mark', 0)$q$, current_setting('tv.org_a'), current_setting('tv.course_a')), '23514', null, 'a pass mark of zero is rejected');

-- =====================================================================
-- 5. Assignments
-- =====================================================================
reset role; select pg_temp.act_as('d4444444-4444-4444-4444-444444444444');
select lives_ok(format($q$insert into public.assignment_submissions (org_id, course_id, assessment_id, body) values (%L, %L, %L, 'My essay')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.essay')), 'an enrolled student can submit an assignment');
select is((select user_id::text from public.assignment_submissions), 'd4444444-4444-4444-4444-444444444444', 'the submission belongs to the caller');
select throws_ok(format($q$insert into public.assignment_submissions (org_id, course_id, assessment_id, body) values (%L, %L, %L, 'again')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.essay')), '23505', null, 'there is one submission per student (edit it instead)');
select throws_ok(format($q$insert into public.assignment_submissions (org_id, course_id, assessment_id, user_id, body) values (%L, %L, %L, 'e5555555-5555-5555-5555-555555555555', 'forged')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.essay')), '42501', null, 'a submission cannot be made in someone else''s name (column grant)');
select throws_ok(format($q$insert into public.assignment_submissions (org_id, course_id, assessment_id, body) values (%L, %L, %L, 'quiz is not an assignment')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.quiz')), '42501', null, 'work cannot be submitted to a quiz');
select throws_ok(format($q$insert into public.assignment_submissions (org_id, course_id, assessment_id, body) values (%L, %L, %L, 'draft')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.draft')), '42501', null, 'work cannot be submitted to an unpublished assignment');
select lives_ok($q$update public.assignment_submissions set body = 'My improved essay'$q$, 'a student can revise their submission before it is graded');
select throws_ok($q$update public.assignment_submissions set points = 10$q$, '42501', null, 'a student cannot give themselves points (column grant)');
select throws_ok($q$update public.assignment_submissions set status = 'graded'$q$, '42501', null, 'a student cannot mark their own work graded (column grant)');

reset role; select pg_temp.act_as('f6666666-6666-6666-6666-666666666666');
select throws_ok(format($q$insert into public.assignment_submissions (org_id, course_id, assessment_id, body) values (%L, %L, %L, 'sneaky')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.essay')), '42501', null, 'an unenrolled student cannot submit');

reset role; select pg_temp.act_as('84848484-8484-8484-8484-848484848484');
select lives_ok(format($q$insert into public.assignment_submissions (org_id, course_id, assessment_id, body) values (%L, %L, %L, 'Hana essay')$q$, current_setting('tv.org_a'), current_setting('tv.course_a'), current_setting('tv.essay')), 'a second student submits');
select is((select count(*) from public.assignment_submissions), 1::bigint, 'a student sees only their own submission');

reset role;
do $$ begin perform set_config('tv.sub_dave', (select id::text from public.assignment_submissions where user_id = 'd4444444-4444-4444-4444-444444444444'), false); end $$;

select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select is((select count(*) from public.assignment_submissions), 2::bigint, 'the course editor sees every submission');

-- ---------- grading ----------
reset role; select pg_temp.act_as('c3333333-3333-3333-3333-333333333333');
select is((select count(*) from public.assignment_submissions), 0::bigint, 'an instructor who does not own the course sees no submissions');
select throws_ok(format($q$select public.grade_submission(%L::uuid, 5, 'nice')$q$, current_setting('tv.sub_dave')), '42501', null, 'an instructor who does not own the course cannot grade it');
reset role; select pg_temp.act_as('d4444444-4444-4444-4444-444444444444');
select throws_ok(format($q$select public.grade_submission(%L::uuid, 10, 'full marks please')$q$, current_setting('tv.sub_dave')), '42501', null, 'a student cannot grade work');
reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select throws_ok(format($q$select public.grade_submission(%L::uuid, 10, 'x')$q$, current_setting('tv.sub_dave')), '42501', null, 'another workspace''s owner cannot grade work');
select is((select count(*) from public.assignment_submissions), 0::bigint, 'bob sees no submissions from alice''s workspace');

reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select throws_ok(format($q$select public.grade_submission(%L::uuid, 11, 'too many')$q$, current_setting('tv.sub_dave')), 'P0001', 'Points must be between 0 and 10', 'points above the maximum are rejected');
select throws_ok(format($q$select public.grade_submission(%L::uuid, -1, 'negative')$q$, current_setting('tv.sub_dave')), 'P0001', 'Points must be between 0 and 10', 'negative points are rejected');
select throws_ok($q$select public.grade_submission('00000000-0000-0000-0000-000000000000', 5, 'x')$q$, 'P0001', 'Submission not found', 'grading a missing submission fails cleanly');
select lives_ok(format($q$select public.grade_submission(%L::uuid, 8, 'Well argued.')$q$, current_setting('tv.sub_dave')), 'the course editor can grade');

reset role; select pg_temp.act_as('d4444444-4444-4444-4444-444444444444');
select is((select points from public.assignment_submissions), 8, 'the student sees their points');
select is((select feedback from public.assignment_submissions), 'Well argued.', '...and the feedback');
select is((select status::text from public.assignment_submissions), 'graded', '...and the graded status');
select lives_ok($q$update public.assignment_submissions set body = 'Changed after grading'$q$, 'an edit after grading is silently filtered');
reset role;
select is((select body from public.assignment_submissions where id = current_setting('tv.sub_dave')::uuid), 'My improved essay', 'graded work is locked');
select is((select count(*) from public.audit_logs where action = 'submission.graded'), 1::bigint, 'grading is audited');

-- =====================================================================
-- 6. Anonymous visitors
-- =====================================================================
select pg_temp.act_as_anon();
select throws_ok($q$select count(*) from public.assessments$q$, '42501', null, 'visitors cannot read assessments');
select throws_ok($q$select count(*) from public.quiz_answer_keys$q$, '42501', null, 'visitors cannot read answer keys');
select throws_ok(format($q$select public.submit_quiz(%L::uuid, '{}'::jsonb)$q$, current_setting('tv.quiz')), '42501', null, 'visitors cannot submit quizzes');
select throws_ok($q$select public.grade_submission('00000000-0000-0000-0000-000000000000', 1, 'x')$q$, '42501', null, 'visitors cannot grade');

-- =====================================================================
-- 7. Deleting content cascades cleanly
-- =====================================================================
reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select lives_ok(format($q$delete from public.assessments where id = %L$q$, current_setting('tv.quiz')), 'a published quiz can be deleted together with its questions');
reset role;
select is((select count(*) from public.quiz_questions where assessment_id = current_setting('tv.quiz')::uuid), 0::bigint, 'its questions are gone');
select is((select count(*) from public.quiz_attempts where assessment_id = current_setting('tv.quiz')::uuid), 0::bigint, '...and its attempts');
select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select lives_ok(format($q$delete from public.courses where id = %L$q$, current_setting('tv.course_a')), 'deleting a course removes everything under it');
reset role;
select is((select count(*) from public.assessments where course_id = current_setting('tv.course_a')::uuid)
        + (select count(*) from public.assignment_submissions where course_id = current_setting('tv.course_a')::uuid)
        + (select count(*) from public.quiz_options where course_id = current_setting('tv.course_a')::uuid), 0::bigint, 'no assessment data is left behind');

select * from finish();
rollback;
