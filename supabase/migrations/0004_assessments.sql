-- =====================================================================
-- Tech Village - Phase 6: assessments (quizzes and assignments)
--
-- Quizzes are graded ON THE SERVER. The answer key lives in its own table that learners can never
-- read, and attempts can only be created by submit_quiz(), so scores cannot be forged.
-- Assignments are written work, reviewed and graded by the people who edit the course.
-- As in Phase 5, every row carries org_id and child rows use COMPOSITE foreign keys, so the
-- database itself refuses links across workspaces or courses.
-- =====================================================================

create type public.assessment_kind as enum ('quiz', 'assignment');
create type public.assessment_status as enum ('draft', 'published');
create type public.submission_status as enum ('submitted', 'graded');

create table public.assessments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  course_id uuid not null,
  kind public.assessment_kind not null,
  title text not null check (char_length(title) between 2 and 160),
  instructions text check (char_length(instructions) <= 5000),
  status public.assessment_status not null default 'draft',
  pass_mark integer not null default 70 check (pass_mark between 1 and 100),        -- quizzes
  max_attempts integer check (max_attempts between 1 and 20),                       -- quizzes; null = unlimited
  max_points integer not null default 100 check (max_points between 1 and 1000),    -- assignments
  due_at timestamptz,
  position integer not null default 0,
  created_by uuid not null default auth.uid() references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (course_id, org_id) references public.courses (id, org_id) on delete cascade,
  unique (id, course_id)
);
create index assessments_course_idx on public.assessments (course_id, position);
create trigger assessments_updated before update on public.assessments
  for each row execute function public.set_updated_at();

create table public.quiz_questions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  course_id uuid not null,
  assessment_id uuid not null,
  position integer not null default 0,
  prompt text not null check (char_length(prompt) between 1 and 1000),
  points integer not null default 1 check (points between 1 and 100),
  foreign key (course_id, org_id) references public.courses (id, org_id) on delete cascade,
  foreign key (assessment_id, course_id) references public.assessments (id, course_id) on delete cascade,
  unique (id, assessment_id)
);
create index quiz_questions_assessment_idx on public.quiz_questions (assessment_id, position);

-- Options deliberately have NO "is_correct" column: learners can read this table.
create table public.quiz_options (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  course_id uuid not null,
  assessment_id uuid not null,
  question_id uuid not null,
  position integer not null default 0,
  label text not null check (char_length(label) between 1 and 500),
  foreign key (course_id, org_id) references public.courses (id, org_id) on delete cascade,
  foreign key (assessment_id, course_id) references public.assessments (id, course_id) on delete cascade,
  foreign key (question_id, assessment_id) references public.quiz_questions (id, assessment_id) on delete cascade,
  unique (id, question_id)
);
create index quiz_options_question_idx on public.quiz_options (question_id, position);

-- The answer key: one correct option per question. Readable only by people who edit the course.
create table public.quiz_answer_keys (
  question_id uuid primary key,
  org_id uuid not null,
  course_id uuid not null,
  assessment_id uuid not null,
  option_id uuid not null,
  foreign key (course_id, org_id) references public.courses (id, org_id) on delete cascade,
  foreign key (assessment_id, course_id) references public.assessments (id, course_id) on delete cascade,
  foreign key (question_id, assessment_id) references public.quiz_questions (id, assessment_id) on delete cascade,
  foreign key (option_id, question_id) references public.quiz_options (id, question_id) on delete cascade
);

create table public.quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  course_id uuid not null,
  assessment_id uuid not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  attempt_no integer not null,
  score_percent integer not null check (score_percent between 0 and 100),
  passed boolean not null,
  answers jsonb not null,
  submitted_at timestamptz not null default now(),
  foreign key (course_id, org_id) references public.courses (id, org_id) on delete cascade,
  foreign key (assessment_id, course_id) references public.assessments (id, course_id) on delete cascade,
  unique (assessment_id, user_id, attempt_no)
);
create index quiz_attempts_user_idx on public.quiz_attempts (user_id, course_id);

create table public.assignment_submissions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  course_id uuid not null,
  assessment_id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 20000),
  status public.submission_status not null default 'submitted',
  points integer check (points >= 0),
  feedback text check (char_length(feedback) <= 5000),
  graded_by uuid references auth.users (id) on delete set null,
  graded_at timestamptz,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (course_id, org_id) references public.courses (id, org_id) on delete cascade,
  foreign key (assessment_id, course_id) references public.assessments (id, course_id) on delete cascade,
  unique (assessment_id, user_id)
);
create index submissions_course_idx on public.assignment_submissions (course_id, assessment_id);
create trigger submissions_updated before update on public.assignment_submissions
  for each row execute function public.set_updated_at();

-- =====================================================================
-- Helpers
-- =====================================================================
create or replace function public.learner_can_see_assessment(p_assessment uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.assessments a
    where a.id = p_assessment and a.status = 'published' and public.is_enrolled(a.course_id)
  );
$$;

create or replace function public.is_assignment(p_assessment uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.assessments where id = p_assessment and kind = 'assignment');
$$;

-- Once a quiz is published, its questions, options and key are frozen: changing them would make
-- earlier scores meaningless. Unpublish first. (Skipped inside cascading deletes.)
create or replace function public.block_quiz_edits_when_published()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_status public.assessment_status;
begin
  if pg_trigger_depth() > 1 then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;
  if tg_op = 'DELETE' then v_id := old.assessment_id; else v_id := new.assessment_id; end if;
  select status into v_status from public.assessments where id = v_id;
  if v_status = 'published' then
    raise exception 'Unpublish the quiz before changing its questions' using errcode = 'P0001';
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end $$;

create trigger quiz_questions_frozen before insert or update or delete on public.quiz_questions
  for each row execute function public.block_quiz_edits_when_published();
create trigger quiz_options_frozen before insert or update or delete on public.quiz_options
  for each row execute function public.block_quiz_edits_when_published();
create trigger quiz_keys_frozen before insert or update or delete on public.quiz_answer_keys
  for each row execute function public.block_quiz_edits_when_published();

-- A quiz can only go live when it is complete.
create or replace function public.validate_assessment_publish()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'published' and new.kind = 'quiz' and (tg_op = 'INSERT' or old.status <> 'published') then
    if not exists (select 1 from public.quiz_questions where assessment_id = new.id) then
      raise exception 'Add at least one question before publishing' using errcode = 'P0001';
    end if;
    if exists (
      select 1 from public.quiz_questions q
      where q.assessment_id = new.id
        and ((select count(*) from public.quiz_options o where o.question_id = q.id) < 2
             or not exists (select 1 from public.quiz_answer_keys k where k.question_id = q.id))
    ) then
      raise exception 'Every question needs at least two options and one correct answer' using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;
create trigger assessments_publish_check before insert or update of status on public.assessments
  for each row execute function public.validate_assessment_publish();

-- =====================================================================
-- Row Level Security
-- =====================================================================
alter table public.assessments            enable row level security;
alter table public.quiz_questions         enable row level security;
alter table public.quiz_options           enable row level security;
alter table public.quiz_answer_keys       enable row level security;
alter table public.quiz_attempts          enable row level security;
alter table public.assignment_submissions enable row level security;

create policy assessments_select on public.assessments for select to authenticated
  using (public.can_edit_course(course_id) or (status = 'published' and public.is_enrolled(course_id)));
create policy assessments_write on public.assessments for all to authenticated
  using (public.can_edit_course(course_id)) with check (public.can_edit_course(course_id));

create policy questions_select on public.quiz_questions for select to authenticated
  using (public.can_edit_course(course_id) or public.learner_can_see_assessment(assessment_id));
create policy questions_write on public.quiz_questions for all to authenticated
  using (public.can_edit_course(course_id)) with check (public.can_edit_course(course_id));

create policy options_select on public.quiz_options for select to authenticated
  using (public.can_edit_course(course_id) or public.learner_can_see_assessment(assessment_id));
create policy options_write on public.quiz_options for all to authenticated
  using (public.can_edit_course(course_id)) with check (public.can_edit_course(course_id));

-- Answer key: editors only, for reading AND writing.
create policy keys_all on public.quiz_answer_keys for all to authenticated
  using (public.can_edit_course(course_id)) with check (public.can_edit_course(course_id));

-- Attempts are read-only for clients; submit_quiz() is the only way to create one.
create policy attempts_select on public.quiz_attempts for select to authenticated using (
  user_id = auth.uid() or public.can_edit_course(course_id) or public.has_permission(org_id, 'reports.view')
);

create policy submissions_select on public.assignment_submissions for select to authenticated using (
  user_id = auth.uid() or public.can_edit_course(course_id) or public.has_permission(org_id, 'reports.view')
);
create policy submissions_insert on public.assignment_submissions for insert to authenticated
  with check (user_id = auth.uid() and public.is_assignment(assessment_id) and public.learner_can_see_assessment(assessment_id));
create policy submissions_update on public.assignment_submissions for update to authenticated
  using (user_id = auth.uid() and status = 'submitted')
  with check (user_id = auth.uid() and status = 'submitted');

-- ---------- Privileges: columns as well as rows ----------
revoke all on public.assessments, public.quiz_questions, public.quiz_options, public.quiz_answer_keys,
              public.quiz_attempts, public.assignment_submissions from anon;

revoke insert, update on public.assessments from authenticated;
grant insert (org_id, course_id, kind, title, instructions, pass_mark, max_attempts, max_points, due_at, position)
  on public.assessments to authenticated;                                  -- always created as drafts
grant update (title, instructions, status, pass_mark, max_attempts, max_points, due_at, position)
  on public.assessments to authenticated;                                  -- kind never changes

revoke insert, update on public.quiz_questions from authenticated;
grant insert (org_id, course_id, assessment_id, prompt, points, position) on public.quiz_questions to authenticated;
grant update (prompt, points, position) on public.quiz_questions to authenticated;

revoke insert, update on public.quiz_options from authenticated;
grant insert (org_id, course_id, assessment_id, question_id, label, position) on public.quiz_options to authenticated;
grant update (label, position) on public.quiz_options to authenticated;

revoke insert, update on public.quiz_answer_keys from authenticated;
grant insert (org_id, course_id, assessment_id, question_id, option_id) on public.quiz_answer_keys to authenticated;
grant update (option_id) on public.quiz_answer_keys to authenticated;

revoke insert, update, delete on public.quiz_attempts from authenticated;

revoke insert, update, delete on public.assignment_submissions from authenticated;
grant insert (org_id, course_id, assessment_id, body) on public.assignment_submissions to authenticated;  -- user_id is always the caller
grant update (body) on public.assignment_submissions to authenticated;

-- =====================================================================
-- RPCs
-- =====================================================================

-- Grades a quiz attempt on the server. Returns the score and which questions were right or wrong,
-- but never the correct answers themselves.
create or replace function public.submit_quiz(p_assessment uuid, p_answers jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  a public.assessments;
  q record;
  v_prev integer;
  v_total integer := 0;
  v_got integer := 0;
  v_score integer;
  v_passed boolean;
  v_results jsonb := '{}'::jsonb;
  v_ok boolean;
begin
  if v_uid is null then
    raise exception 'Sign in to take this quiz' using errcode = '28000';
  end if;
  select * into a from public.assessments where id = p_assessment;
  if not found or a.kind <> 'quiz' or a.status <> 'published' then
    raise exception 'Quiz not available' using errcode = 'P0001';
  end if;
  if not public.is_enrolled(a.course_id) then
    raise exception 'Enrol in the course to take this quiz' using errcode = '42501';
  end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    raise exception 'Invalid answers' using errcode = 'P0001';
  end if;
  if (select count(*) from jsonb_object_keys(p_answers)) > 500 then
    raise exception 'Invalid answers' using errcode = 'P0001';
  end if;

  select count(*) into v_prev from public.quiz_attempts where assessment_id = a.id and user_id = v_uid;
  if a.max_attempts is not null and v_prev >= a.max_attempts then
    raise exception 'No attempts left' using errcode = 'P0001';
  end if;

  for q in
    select qq.id, qq.points, k.option_id
    from public.quiz_questions qq
    join public.quiz_answer_keys k on k.question_id = qq.id
    where qq.assessment_id = a.id
  loop
    v_total := v_total + q.points;
    v_ok := (p_answers ->> q.id::text) is not null and (p_answers ->> q.id::text) = q.option_id::text;
    if v_ok then v_got := v_got + q.points; end if;
    v_results := v_results || jsonb_build_object(q.id::text, v_ok);
  end loop;

  if v_total = 0 then
    raise exception 'This quiz has no questions' using errcode = 'P0001';
  end if;
  v_score := round(100.0 * v_got / v_total)::integer;
  v_passed := v_score >= a.pass_mark;

  insert into public.quiz_attempts (org_id, course_id, assessment_id, user_id, attempt_no, score_percent, passed, answers)
  values (a.org_id, a.course_id, a.id, v_uid, v_prev + 1, v_score, v_passed, p_answers);

  return jsonb_build_object('attempt_no', v_prev + 1, 'score_percent', v_score, 'passed', v_passed, 'results', v_results);
end $$;

-- Instructors grade an assignment submission.
create or replace function public.grade_submission(p_submission uuid, p_points integer, p_feedback text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  s public.assignment_submissions;
  v_max integer;
begin
  if v_uid is null then
    raise exception 'Sign in first' using errcode = '28000';
  end if;
  select * into s from public.assignment_submissions where id = p_submission;
  if not found then
    raise exception 'Submission not found' using errcode = 'P0001';
  end if;
  if not public.can_edit_course(s.course_id) then
    raise exception 'You do not have permission to grade this work' using errcode = '42501';
  end if;
  select max_points into v_max from public.assessments where id = s.assessment_id;
  if p_points is null or p_points < 0 or p_points > v_max then
    raise exception 'Points must be between 0 and %', v_max using errcode = 'P0001';
  end if;
  update public.assignment_submissions
    set status = 'graded', points = p_points, feedback = nullif(trim(p_feedback), ''),
        graded_by = v_uid, graded_at = now()
    where id = p_submission;
  perform public.log_audit(s.org_id, 'submission.graded', 'assignment_submission', p_submission::text);
end $$;

revoke all on function public.submit_quiz(uuid, jsonb) from public, anon;
revoke all on function public.grade_submission(uuid, integer, text) from public, anon;
grant execute on function public.submit_quiz(uuid, jsonb) to authenticated;
grant execute on function public.grade_submission(uuid, integer, text) to authenticated;
