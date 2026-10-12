-- =====================================================================
-- Tech Village - Phase 5: LMS core and invitations
--
-- Every row carries org_id (the tenant). Child rows are tied to their parent with COMPOSITE foreign
-- keys that include org_id, so the database itself refuses a lesson that points at another
-- tenant's course, even if a client lies about org_id.
-- Applies identically to the official Tech Village LMS and to customer workspaces.
-- =====================================================================

create type public.course_status as enum ('draft', 'published', 'archived');
create type public.enrolment_status as enum ('active', 'withdrawn');
create type public.block_type as enum ('text', 'video');
create type public.invitation_status as enum ('pending', 'accepted', 'revoked');

-- ---------- Courses ----------
create table public.courses (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations (id) on delete cascade,
  title text not null check (char_length(title) between 2 and 160),
  summary text check (char_length(summary) <= 500),
  status public.course_status not null default 'draft',
  created_by uuid not null default auth.uid() references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, org_id)
);
create index courses_org_idx on public.courses (org_id, status);
create trigger courses_updated before update on public.courses
  for each row execute function public.set_updated_at();

create table public.modules (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  course_id uuid not null,
  title text not null check (char_length(title) between 1 and 160),
  position integer not null default 0,
  created_at timestamptz not null default now(),
  foreign key (course_id, org_id) references public.courses (id, org_id) on delete cascade,
  unique (id, course_id)
);
create index modules_course_idx on public.modules (course_id, position);

create table public.lessons (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  course_id uuid not null,
  module_id uuid not null,
  title text not null check (char_length(title) between 1 and 160),
  position integer not null default 0,
  created_at timestamptz not null default now(),
  foreign key (course_id, org_id) references public.courses (id, org_id) on delete cascade,
  foreign key (module_id, course_id) references public.modules (id, course_id) on delete cascade,
  unique (id, course_id)
);
create index lessons_module_idx on public.lessons (module_id, position);

-- A lesson is an ordered list of blocks, so text and video can be mixed in one lesson.
-- Text is stored as plain text and rendered as text (never as HTML). Video URLs are limited to
-- canonical YouTube and Vimeo links; the app turns them into embeds from the parsed ID.
create table public.lesson_blocks (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  course_id uuid not null,
  lesson_id uuid not null,
  position integer not null default 0,
  block_type public.block_type not null,
  body text,
  video_url text,
  created_at timestamptz not null default now(),
  foreign key (course_id, org_id) references public.courses (id, org_id) on delete cascade,
  foreign key (lesson_id, course_id) references public.lessons (id, course_id) on delete cascade,
  constraint block_shape check (
    (block_type = 'text' and char_length(coalesce(body, '')) between 1 and 20000 and video_url is null)
    or
    (block_type = 'video' and body is null and video_url ~*
      '^https://(www\.)?(youtube\.com/watch\?v=[A-Za-z0-9_-]{11}|youtu\.be/[A-Za-z0-9_-]{11}|vimeo\.com/[0-9]{6,12})$')
  )
);
create index lesson_blocks_lesson_idx on public.lesson_blocks (lesson_id, position);

-- ---------- Enrolments and progress ----------
create table public.enrolments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  course_id uuid not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  status public.enrolment_status not null default 'active',
  created_at timestamptz not null default now(),
  foreign key (course_id, org_id) references public.courses (id, org_id) on delete cascade,
  unique (course_id, user_id)
);
create index enrolments_user_idx on public.enrolments (user_id);
create index enrolments_org_idx on public.enrolments (org_id, status);

create table public.lesson_progress (
  org_id uuid not null,
  course_id uuid not null,
  lesson_id uuid not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  completed_at timestamptz not null default now(),
  primary key (lesson_id, user_id),
  foreign key (course_id, org_id) references public.courses (id, org_id) on delete cascade,
  foreign key (lesson_id, course_id) references public.lessons (id, course_id) on delete cascade
);
create index lesson_progress_user_idx on public.lesson_progress (user_id, course_id);

-- ---------- Invitations ----------
-- Only a SHA-256 hash of the secret token is stored. The raw token is shown once to the inviter.
create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations (id) on delete cascade,
  email text not null check (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  role_id uuid not null references public.roles (id),
  token_hash text not null unique,
  status public.invitation_status not null default 'pending',
  invited_by uuid default auth.uid() references auth.users (id) on delete set null,
  expires_at timestamptz not null default now() + interval '14 days',
  created_at timestamptz not null default now(),
  accepted_by uuid references auth.users (id) on delete set null,
  accepted_at timestamptz
);
create index invitations_org_idx on public.invitations (org_id, status);

-- =====================================================================
-- Access helpers
-- =====================================================================
create or replace function public.can_edit_course(p_course uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.courses c
    where c.id = p_course
      and (public.has_permission(c.org_id, 'courses.manage')
           or (public.has_permission(c.org_id, 'courses.create') and c.created_by = auth.uid()))
  );
$$;

-- Active enrolment, published course, active workspace and still an active member.
create or replace function public.is_enrolled(p_course uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.enrolments e
    join public.courses c on c.id = e.course_id
    where e.course_id = p_course
      and e.user_id = auth.uid()
      and e.status = 'active'
      and c.status = 'published'
      and public.has_org_access(c.org_id)
  );
$$;

create or replace function public.is_published_course(p_course uuid, p_org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.courses where id = p_course and org_id = p_org and status = 'published');
$$;

create or replace function public.is_active_member(p_org uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.memberships where org_id = p_org and user_id = p_user and status = 'active');
$$;

-- =====================================================================
-- Plan limits enforced in the database (the official LMS is exempt)
-- =====================================================================
create or replace function public.enforce_course_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_limit int; v_count int;
begin
  if tg_op = 'UPDATE' and not (old.status = 'archived' and new.status <> 'archived') then
    return new;
  end if;
  if exists (select 1 from public.organisations where id = new.org_id and is_platform_tenant) then
    return new;
  end if;
  v_limit := (public.get_entitlement(new.org_id, 'max_courses') ->> 'limit')::int;
  if v_limit is null then
    raise exception 'This workspace has no active plan' using errcode = 'P0001';
  end if;
  select count(*) into v_count from public.courses
    where org_id = new.org_id and status <> 'archived' and id <> new.id;
  if v_count >= v_limit then
    raise exception 'Your plan allows % course(s). Upgrade to add more.', v_limit using errcode = 'P0001';
  end if;
  return new;
end $$;
create trigger courses_limit before insert or update of status on public.courses
  for each row execute function public.enforce_course_limit();

create or replace function public.enforce_student_limit()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_limit int; v_count int;
begin
  if new.status <> 'active' then return new; end if;
  if tg_op = 'UPDATE' and old.status = 'active' then return new; end if;
  if exists (select 1 from public.organisations where id = new.org_id and is_platform_tenant) then
    return new;
  end if;
  -- A learner already enrolled somewhere in this workspace is already counted.
  if exists (select 1 from public.enrolments e
             where e.org_id = new.org_id and e.user_id = new.user_id and e.status = 'active' and e.id <> new.id) then
    return new;
  end if;
  v_limit := (public.get_entitlement(new.org_id, 'max_students') ->> 'limit')::int;
  if v_limit is null then
    raise exception 'This workspace has no active plan' using errcode = 'P0001';
  end if;
  select count(distinct user_id) into v_count from public.enrolments
    where org_id = new.org_id and status = 'active';
  if v_count >= v_limit then
    raise exception 'Your plan allows % learner(s). Upgrade to enrol more.', v_limit using errcode = 'P0001';
  end if;
  return new;
end $$;
create trigger enrolments_limit before insert or update of status on public.enrolments
  for each row execute function public.enforce_student_limit();

-- =====================================================================
-- Row Level Security
-- =====================================================================
alter table public.courses         enable row level security;
alter table public.modules         enable row level security;
alter table public.lessons         enable row level security;
alter table public.lesson_blocks   enable row level security;
alter table public.enrolments      enable row level security;
alter table public.lesson_progress enable row level security;
alter table public.invitations     enable row level security;

-- courses: staff see what they manage; members see published courses of their own workspace
create policy courses_select on public.courses for select to authenticated using (
  public.has_permission(org_id, 'courses.manage')
  or (public.has_permission(org_id, 'courses.create') and created_by = auth.uid())
  or (status = 'published' and public.has_org_access(org_id))
);
create policy courses_insert on public.courses for insert to authenticated
  with check (public.has_permission(org_id, 'courses.create') and created_by = auth.uid());
create policy courses_update on public.courses for update to authenticated
  using (public.can_edit_course(id)) with check (public.can_edit_course(id));
create policy courses_delete on public.courses for delete to authenticated
  using (public.can_edit_course(id));

-- course content: editors, and learners with an active enrolment in a published course
create policy modules_select on public.modules for select to authenticated
  using (public.can_edit_course(course_id) or public.is_enrolled(course_id));
create policy modules_write on public.modules for all to authenticated
  using (public.can_edit_course(course_id)) with check (public.can_edit_course(course_id));

create policy lessons_select on public.lessons for select to authenticated
  using (public.can_edit_course(course_id) or public.is_enrolled(course_id));
create policy lessons_write on public.lessons for all to authenticated
  using (public.can_edit_course(course_id)) with check (public.can_edit_course(course_id));

create policy blocks_select on public.lesson_blocks for select to authenticated
  using (public.can_edit_course(course_id) or public.is_enrolled(course_id));
create policy blocks_write on public.lesson_blocks for all to authenticated
  using (public.can_edit_course(course_id)) with check (public.can_edit_course(course_id));

-- enrolments: self-enrol in published courses of your own workspace, or staff enrol members
create policy enrolments_select on public.enrolments for select to authenticated using (
  user_id = auth.uid()
  or public.has_permission(org_id, 'enrolments.manage')
  or public.has_permission(org_id, 'reports.view')
);
create policy enrolments_insert on public.enrolments for insert to authenticated with check (
  (user_id = auth.uid() and public.has_org_access(org_id) and public.is_published_course(course_id, org_id))
  or (public.has_permission(org_id, 'enrolments.manage') and public.is_active_member(org_id, user_id)
      and public.is_published_course(course_id, org_id))
);
create policy enrolments_update on public.enrolments for update to authenticated
  using (user_id = auth.uid() or public.has_permission(org_id, 'enrolments.manage'))
  with check (user_id = auth.uid() or public.has_permission(org_id, 'enrolments.manage'));

-- progress: your own rows; staff with reporting rights can read
create policy progress_select on public.lesson_progress for select to authenticated using (
  user_id = auth.uid()
  or public.has_permission(org_id, 'reports.view')
  or public.has_permission(org_id, 'enrolments.manage')
);
create policy progress_insert on public.lesson_progress for insert to authenticated
  with check (user_id = auth.uid() and public.is_enrolled(course_id));
create policy progress_delete on public.lesson_progress for delete to authenticated
  using (user_id = auth.uid());

-- invitations: readable by people who manage members; written only by the RPCs below
create policy invitations_select on public.invitations for select to authenticated
  using (public.has_permission(org_id, 'members.manage'));

-- ---------- Privileges: columns as well as rows ----------
revoke all on public.courses, public.modules, public.lessons, public.lesson_blocks,
              public.enrolments, public.lesson_progress, public.invitations from anon;

revoke insert, update on public.courses from authenticated;
grant insert (org_id, title, summary) on public.courses to authenticated;   -- new courses are always drafts
grant update (title, summary, status) on public.courses to authenticated;

revoke insert, update on public.modules from authenticated;
grant insert (org_id, course_id, title, position) on public.modules to authenticated;
grant update (title, position) on public.modules to authenticated;

revoke insert, update on public.lessons from authenticated;
grant insert (org_id, course_id, module_id, title, position) on public.lessons to authenticated;
grant update (title, position, module_id) on public.lessons to authenticated;

revoke insert, update on public.lesson_blocks from authenticated;
grant insert (org_id, course_id, lesson_id, block_type, body, video_url, position) on public.lesson_blocks to authenticated;
grant update (body, video_url, position) on public.lesson_blocks to authenticated;

revoke insert, update, delete on public.enrolments from authenticated;
grant insert (org_id, course_id, user_id) on public.enrolments to authenticated;
grant update (status) on public.enrolments to authenticated;

revoke insert, update on public.lesson_progress from authenticated;
grant insert (org_id, course_id, lesson_id, user_id) on public.lesson_progress to authenticated;

revoke insert, update, delete on public.invitations from authenticated;

-- =====================================================================
-- Invitation and member-management RPCs
-- =====================================================================

-- Returns the raw token ONCE. The inviter shares the link; only a hash is stored.
create or replace function public.create_invitation(p_org uuid, p_email text, p_role_key text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(trim(p_email));
  v_role uuid;
  v_token text;
begin
  if v_uid is null then
    raise exception 'Sign in first' using errcode = '28000';
  end if;
  if not public.has_permission(p_org, 'members.manage') then
    raise exception 'You do not have permission to invite people' using errcode = '42501';
  end if;
  if p_role_key = 'owner' then
    raise exception 'Owners cannot be invited';
  end if;
  v_role := public.system_role_id(p_role_key);
  if v_role is null then
    raise exception 'Unknown role';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid email address';
  end if;
  if exists (select 1 from auth.users u
             join public.memberships m on m.user_id = u.id and m.org_id = p_org and m.status = 'active'
             where lower(u.email) = v_email) then
    raise exception 'That person is already a member';
  end if;
  if (select count(*) from public.invitations where org_id = p_org and status = 'pending') >= 200 then
    raise exception 'Too many pending invitations. Revoke some first.';
  end if;

  update public.invitations set status = 'revoked'
    where org_id = p_org and email = v_email and status = 'pending';

  -- Two random UUIDs give about 244 bits of entropy. Only the hash is stored.
  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  insert into public.invitations (org_id, email, role_id, token_hash)
  values (p_org, v_email, v_role, encode(sha256(convert_to(v_token, 'utf8')), 'hex'));

  perform public.log_audit(p_org, 'invitation.created', 'invitation', null,
                           jsonb_build_object('role', p_role_key));
  return v_token;
end $$;

create or replace function public.revoke_invitation(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_org uuid;
begin
  select org_id into v_org from public.invitations where id = p_id;
  if v_org is null or not public.has_permission(v_org, 'members.manage') then
    raise exception 'You do not have permission to do that' using errcode = '42501';
  end if;
  update public.invitations set status = 'revoked' where id = p_id and status = 'pending';
  perform public.log_audit(v_org, 'invitation.revoked', 'invitation', p_id::text);
end $$;

-- What the person holding a link is about to join. Reveals nothing without the token.
create or replace function public.invitation_preview(p_token text)
returns table (workspace_name text, role_name text, invited_email text, status public.invitation_status, expired boolean)
language sql stable security definer set search_path = '' as $$
  select o.workspace_name, r.name, i.email, i.status, i.expires_at < now()
  from public.invitations i
  join public.organisations o on o.id = i.org_id
  join public.roles r on r.id = i.role_id
  where auth.uid() is not null
    and i.token_hash = encode(sha256(convert_to(p_token, 'utf8')), 'hex');
$$;

-- Accepting requires a signed-in account whose VERIFIED email matches the invitation.
create or replace function public.accept_invitation(p_token text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_inv public.invitations;
  v_email text;
  v_confirmed timestamptz;
begin
  if v_uid is null then
    raise exception 'Sign in to accept this invitation' using errcode = '28000';
  end if;
  select * into v_inv from public.invitations
    where token_hash = encode(sha256(convert_to(p_token, 'utf8')), 'hex') for update;
  if not found or v_inv.status <> 'pending' then
    raise exception 'This invitation is no longer valid';
  end if;
  if v_inv.expires_at < now() then
    raise exception 'This invitation has expired. Ask for a new one.';
  end if;
  if not exists (select 1 from public.organisations where id = v_inv.org_id and status = 'active') then
    raise exception 'This workspace is not available';
  end if;

  select email, email_confirmed_at into v_email, v_confirmed from auth.users where id = v_uid;
  if v_confirmed is null or lower(v_email) <> v_inv.email then
    raise exception 'This invitation was sent to a different email address' using errcode = '42501';
  end if;

  insert into public.memberships (org_id, user_id, role_id)
  values (v_inv.org_id, v_uid, v_inv.role_id)
  on conflict (org_id, user_id) do nothing;

  update public.invitations set status = 'accepted', accepted_by = v_uid, accepted_at = now()
    where id = v_inv.id;
  perform public.log_audit(v_inv.org_id, 'invitation.accepted', 'invitation', v_inv.id::text);
  return v_inv.org_id;
end $$;

-- Members of a workspace with names and emails, for people who manage members.
create or replace function public.list_members(p_org uuid)
returns table (
  membership_id uuid, user_id uuid, full_name text, email text,
  role_key text, role_name text, status public.membership_status, created_at timestamptz
) language sql stable security definer set search_path = '' as $$
  select m.id, m.user_id, p.full_name, u.email::text, r.key, r.name, m.status, m.created_at
  from public.memberships m
  join public.roles r on r.id = m.role_id
  join auth.users u on u.id = m.user_id
  left join public.profiles p on p.id = m.user_id
  where m.org_id = p_org and public.has_permission(p_org, 'members.manage')
  order by m.created_at;
$$;

revoke all on function public.create_invitation(uuid, text, text) from public, anon;
revoke all on function public.revoke_invitation(uuid) from public, anon;
revoke all on function public.invitation_preview(text) from public, anon;
revoke all on function public.accept_invitation(text) from public, anon;
revoke all on function public.list_members(uuid) from public, anon;
grant execute on function public.create_invitation(uuid, text, text) to authenticated;
grant execute on function public.revoke_invitation(uuid) to authenticated;
grant execute on function public.invitation_preview(text) to authenticated;
grant execute on function public.accept_invitation(text) to authenticated;
grant execute on function public.list_members(uuid) to authenticated;

-- =====================================================================
-- Third sign-up intent: people who create an account in order to accept an invitation.
-- They are neither "Join Tech Village" learners nor workspace creators, so they get no
-- automatic membership and are never nudged into workspace setup.
-- =====================================================================
alter table public.profiles drop constraint profiles_signup_intent_check;
alter table public.profiles add constraint profiles_signup_intent_check
  check (signup_intent in ('learner', 'workspace', 'invited'));

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_intent text := new.raw_user_meta_data ->> 'signup_intent';
  v_org uuid;
begin
  if v_intent is null or v_intent not in ('learner', 'workspace', 'invited') then
    v_intent := null;
  end if;

  insert into public.profiles (id, full_name, signup_intent)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''), v_intent);

  if v_intent = 'learner' then
    select id into v_org from public.organisations where is_platform_tenant;
    if v_org is not null then
      insert into public.memberships (org_id, user_id, role_id)
      values (v_org, new.id, public.system_role_id('student'))
      on conflict (org_id, user_id) do nothing;
    end if;
  end if;
  return new;
end $$;
