-- =====================================================================
-- Tech Village - Phase 1 foundation (V3.1)
--
-- Model
--   * One table of organisations. An organisation IS a workspace (1:1) and is the tenant boundary.
--   * Exactly one organisation is the platform tenant: the official Tech Village LMS.
--     Individual learners join it as students.
--   * Every other organisation is an independent customer workspace with its own owner.
--   * No sub-accounts, campuses or nested organisations.
--   * Tenant isolation is enforced by RLS. Privileged writes go through SECURITY DEFINER
--     functions that re-check access on the server.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- Enums ----------
create type public.org_type as enum (
  'school', 'university_college', 'training_academy', 'coding_bootcamp',
  'private_tutoring', 'independent_instructor', 'corporate_training', 'other'
);
create type public.org_status as enum ('active', 'suspended');
create type public.membership_status as enum ('invited', 'active', 'suspended');
create type public.subscription_status as enum
  ('trialing', 'active', 'past_due', 'canceled', 'expired');
create type public.billing_interval as enum ('month', 'year');

-- ---------- Utility ----------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ---------- Profiles ----------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  avatar_url text,
  country text,
  -- Which sign-up journey the person chose. Used only to route them after verification.
  signup_intent text check (signup_intent in ('learner', 'workspace')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger profiles_updated before update on public.profiles
  for each row execute function public.set_updated_at();

-- ---------- Platform admins (managed with the service role only) ----------
create table public.platform_admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.platform_admins enable row level security;
-- No policies: clients can never read or write this table directly.

-- ---------- Organisations / workspaces ----------
create table public.organisations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 120),            -- organisation name
  workspace_name text not null check (char_length(workspace_name) between 2 and 120),
  slug text not null unique                                                   -- workspace identifier
    check (slug ~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$'),
  org_type public.org_type not null default 'other',
  description text check (char_length(description) <= 1000),
  country text,
  contact_email text check (contact_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  contact_phone text check (char_length(contact_phone) <= 40),
  website text check (website ~* '^https?://\S+$'),
  logo_url text,
  is_platform_tenant boolean not null default false,
  status public.org_status not null default 'active',
  branding jsonb not null default '{}'::jsonb,
  settings jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger organisations_updated before update on public.organisations
  for each row execute function public.set_updated_at();
-- At most one official Tech Village LMS.
create unique index one_platform_tenant on public.organisations (is_platform_tenant) where is_platform_tenant;

-- ---------- Permissions and roles ----------
create table public.permissions (
  key text primary key,
  description text not null
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references public.organisations (id) on delete cascade, -- null = system role
  key text not null,
  name text not null,
  is_system boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index roles_key_unique
  on public.roles (coalesce(org_id, '00000000-0000-0000-0000-000000000000'::uuid), key);

create table public.role_permissions (
  role_id uuid not null references public.roles (id) on delete cascade,
  permission_key text not null references public.permissions (key) on delete cascade,
  primary key (role_id, permission_key)
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organisations (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role_id uuid not null references public.roles (id),
  status public.membership_status not null default 'active',
  created_at timestamptz not null default now(),
  unique (org_id, user_id)
);
create index memberships_user_idx on public.memberships (user_id);

-- ---------- Plans, entitlements, subscriptions ----------
create table public.plans (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  name text not null,
  description text,
  price_month_minor integer not null default 0,
  price_year_minor integer not null default 0,
  currency text not null default 'NGN',
  trial_days integer not null default 0,
  is_public boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- One row per limit or flag. Plans are configured by data, never by code changes.
create table public.plan_entitlements (
  plan_id uuid not null references public.plans (id) on delete cascade,
  key text not null,
  value jsonb not null,
  primary key (plan_id, key)
);

-- A subscription belongs to the organisation workspace, never to a person's learner account.
create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null unique references public.organisations (id) on delete cascade,
  plan_id uuid not null references public.plans (id),
  status public.subscription_status not null default 'trialing',
  billing_interval public.billing_interval not null default 'month',
  trial_ends_at timestamptz,
  current_period_end timestamptz,
  provider text,
  provider_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger subscriptions_updated before update on public.subscriptions
  for each row execute function public.set_updated_at();

-- ---------- Audit log ----------
create table public.audit_logs (
  id bigint generated always as identity primary key,
  org_id uuid references public.organisations (id) on delete set null,
  actor_id uuid references auth.users (id) on delete set null,
  action text not null,
  entity_type text,
  entity_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index audit_logs_org_idx on public.audit_logs (org_id, created_at desc);

-- =====================================================================
-- Access helper functions
-- SECURITY DEFINER so policies can call them without recursing into RLS.
-- search_path is pinned to avoid schema hijacking.
-- =====================================================================

create or replace function public.is_platform_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.platform_admins where user_id = auth.uid());
$$;

create or replace function public.has_org_access(p_org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.memberships m
    join public.organisations o on o.id = m.org_id
    where m.org_id = p_org
      and m.user_id = auth.uid()
      and m.status = 'active'
      and o.status = 'active'
  );
$$;

create or replace function public.has_permission(p_org uuid, p_permission text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.memberships m
    join public.organisations o on o.id = m.org_id
    join public.role_permissions rp on rp.role_id = m.role_id
    where m.org_id = p_org
      and m.user_id = auth.uid()
      and m.status = 'active'
      and o.status = 'active'
      and rp.permission_key = p_permission
  );
$$;

create or replace function public.shares_org_with(p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.memberships mine
    join public.memberships theirs on theirs.org_id = mine.org_id
    where mine.user_id = auth.uid() and mine.status = 'active'
      and theirs.user_id = p_user
  );
$$;

create or replace function public.system_role_id(p_key text)
returns uuid language sql stable security definer set search_path = '' as $$
  select id from public.roles where org_id is null and key = p_key;
$$;

create or replace function public.owner_role_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select public.system_role_id('owner');
$$;

-- Entitlement value for a workspace. Null when there is no live subscription or the key is missing.
create or replace function public.get_entitlement(p_org uuid, p_key text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select pe.value
  from public.subscriptions s
  join public.plan_entitlements pe on pe.plan_id = s.plan_id and pe.key = p_key
  where s.org_id = p_org
    and s.status in ('trialing', 'active', 'past_due');
$$;

create or replace function public.log_audit(
  p_org uuid, p_action text, p_entity_type text default null,
  p_entity_id text default null, p_metadata jsonb default '{}'::jsonb
) returns void language sql security definer set search_path = '' as $$
  insert into public.audit_logs (org_id, actor_id, action, entity_type, entity_id, metadata)
  values (p_org, auth.uid(), p_action, p_entity_type, p_entity_id, p_metadata);
$$;
revoke all on function public.log_audit(uuid, text, text, text, jsonb) from public, anon, authenticated;

-- ---------- New user handling ----------
-- "Join Tech Village" sign-ups (signup_intent = learner) become students of the official LMS.
-- "Create your own LMS" sign-ups get NO membership anywhere until they complete workspace setup.
-- Metadata is user-supplied, which is safe here: the learner journey is open to everyone and
-- only ever grants the student role in the official LMS.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_intent text := new.raw_user_meta_data ->> 'signup_intent';
  v_org uuid;
begin
  if v_intent is null or v_intent not in ('learner', 'workspace') then
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

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- =====================================================================
-- Row Level Security
-- =====================================================================
alter table public.profiles          enable row level security;
alter table public.organisations     enable row level security;
alter table public.permissions       enable row level security;
alter table public.roles             enable row level security;
alter table public.role_permissions  enable row level security;
alter table public.memberships       enable row level security;
alter table public.plans             enable row level security;
alter table public.plan_entitlements enable row level security;
alter table public.subscriptions     enable row level security;
alter table public.audit_logs        enable row level security;

-- profiles
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.shares_org_with(id));
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- organisations (creation happens through RPCs only)
create policy orgs_select on public.organisations for select to authenticated
  using (public.has_org_access(id) or public.is_platform_admin());
create policy orgs_update on public.organisations for update to authenticated
  using (public.has_permission(id, 'org.manage'))
  with check (public.has_permission(id, 'org.manage'));

-- permissions catalogue
create policy permissions_select on public.permissions for select to authenticated using (true);

-- roles: system roles are readable by everyone signed in; custom roles belong to one workspace
create policy roles_select on public.roles for select to authenticated
  using (org_id is null or public.has_org_access(org_id) or public.is_platform_admin());
create policy roles_insert on public.roles for insert to authenticated
  with check (org_id is not null and not is_system and public.has_permission(org_id, 'roles.manage'));
create policy roles_update on public.roles for update to authenticated
  using (org_id is not null and not is_system and public.has_permission(org_id, 'roles.manage'))
  with check (org_id is not null and not is_system and public.has_permission(org_id, 'roles.manage'));
create policy roles_delete on public.roles for delete to authenticated
  using (org_id is not null and not is_system and public.has_permission(org_id, 'roles.manage'));

create policy role_permissions_select on public.role_permissions for select to authenticated
  using (exists (
    select 1 from public.roles r
    where r.id = role_id
      and (r.org_id is null or public.has_org_access(r.org_id) or public.is_platform_admin())
  ));
create policy role_permissions_write on public.role_permissions for all to authenticated
  using (exists (
    select 1 from public.roles r
    where r.id = role_id and r.org_id is not null and not r.is_system
      and public.has_permission(r.org_id, 'roles.manage')
  ))
  with check (exists (
    select 1 from public.roles r
    where r.id = role_id and r.org_id is not null and not r.is_system
      and public.has_permission(r.org_id, 'roles.manage')
  ));

-- memberships: staff with members.manage can manage, but never mint owners
create policy memberships_select on public.memberships for select to authenticated
  using (user_id = auth.uid()
         or public.has_permission(org_id, 'members.manage')
         or public.is_platform_admin());
create policy memberships_insert on public.memberships for insert to authenticated
  with check (public.has_permission(org_id, 'members.manage')
              and role_id <> public.owner_role_id());
create policy memberships_update on public.memberships for update to authenticated
  using (public.has_permission(org_id, 'members.manage') and role_id <> public.owner_role_id())
  with check (public.has_permission(org_id, 'members.manage') and role_id <> public.owner_role_id());
create policy memberships_delete on public.memberships for delete to authenticated
  using (public.has_permission(org_id, 'members.manage') and role_id <> public.owner_role_id());

-- plans: public catalogue readable by everyone, managed by platform admins
create policy plans_select on public.plans for select to anon, authenticated
  using ((is_public and is_active) or public.is_platform_admin());
create policy plans_admin_write on public.plans for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
create policy plan_entitlements_select on public.plan_entitlements for select to anon, authenticated
  using (exists (select 1 from public.plans p
                 where p.id = plan_id and ((p.is_public and p.is_active) or public.is_platform_admin())));
create policy plan_entitlements_admin_write on public.plan_entitlements for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

-- subscriptions: read-only for billing staff; writes come from RPCs and payment webhooks (service role)
create policy subscriptions_select on public.subscriptions for select to authenticated
  using (public.has_permission(org_id, 'billing.manage') or public.is_platform_admin());

-- audit logs: read-only
create policy audit_select on public.audit_logs for select to authenticated
  using ((org_id is not null and public.has_permission(org_id, 'audit.view')) or public.is_platform_admin());

-- Platform admins can see workspaces, plans and subscriptions for support and billing, but
-- has_org_access() deliberately excludes them, so a customer's students and courses stay private.

-- ---------- Column and table privileges (defence in depth) ----------
-- RLS decides which ROWS a user may touch; these grants decide which COLUMNS.
-- Without them an owner could flip is_platform_tenant or status on their own workspace.
revoke insert, update, delete on public.organisations from anon, authenticated;
grant update (name, workspace_name, org_type, description, country, contact_email,
              contact_phone, website, logo_url, branding, settings)
  on public.organisations to authenticated;

revoke update on public.memberships from anon, authenticated;
grant update (role_id, status) on public.memberships to authenticated;

revoke insert, update, delete on public.subscriptions, public.audit_logs from anon, authenticated;
revoke all on public.platform_admins from anon, authenticated;

-- Visitors who are not signed in may read only the public plan catalogue.
revoke all on public.profiles, public.organisations, public.permissions, public.roles,
              public.role_permissions, public.memberships, public.subscriptions, public.audit_logs
  from anon;

-- =====================================================================
-- Seed: permissions, system roles, plans, and the official Tech Village LMS
-- =====================================================================
insert into public.permissions (key, description) values
  ('org.manage',        'Edit organisation details and settings'),
  ('org.branding',      'Edit branding and logo'),
  ('members.manage',    'Invite and manage members'),
  ('roles.manage',      'Create and edit custom roles'),
  ('courses.view',      'View courses'),
  ('courses.create',    'Create courses'),
  ('courses.manage',    'Edit and publish any course'),
  ('enrolments.manage', 'Manage enrolments'),
  ('billing.manage',    'View and manage billing'),
  ('reports.view',      'View reports and analytics'),
  ('audit.view',        'View the audit log');

insert into public.roles (org_id, key, name, is_system) values
  (null, 'owner',              'Owner',              true),
  (null, 'admin',              'Administrator',      true),
  (null, 'instructor',         'Instructor',         true),
  (null, 'teaching_assistant', 'Teaching assistant', true),
  (null, 'student',            'Student',            true),
  (null, 'mentor',             'Mentor',             true);  -- used by the official LMS

insert into public.role_permissions (role_id, permission_key)
select r.id, p.key from public.roles r
join public.permissions p on (
  (r.key = 'owner') or
  (r.key = 'admin'              and p.key in ('org.manage','org.branding','members.manage','courses.view','courses.create','courses.manage','enrolments.manage','reports.view')) or
  (r.key = 'instructor'         and p.key in ('courses.view','courses.create')) or
  (r.key = 'teaching_assistant' and p.key in ('courses.view','enrolments.manage')) or
  (r.key = 'student'            and p.key in ('courses.view')) or
  (r.key = 'mentor'             and p.key in ('courses.view'))
)
where r.org_id is null;

-- Starter plans. Prices are placeholders in kobo (NGN minor units); edit in the admin UI later.
insert into public.plans (key, name, description, price_month_minor, price_year_minor, trial_days) values
  ('starter',     'Starter',     'For individual tutors and course creators',  0,        0,         0),
  ('growth',      'Growth',      'For academies and small training providers', 2500000, 25000000, 14),
  ('institution', 'Institution', 'For schools, universities and companies',    9000000, 90000000, 14);

insert into public.plan_entitlements (plan_id, key, value)
select p.id, e.key, e.value from public.plans p
join (values
  ('starter',     'max_instructors', '{"limit": 1}'::jsonb),
  ('starter',     'max_students',    '{"limit": 25}'),
  ('starter',     'max_courses',     '{"limit": 3}'),
  ('starter',     'storage_mb',      '{"limit": 500}'),
  ('starter',     'coding_labs',     '{"enabled": false}'),
  ('starter',     'custom_branding', '{"enabled": false}'),
  ('starter',     'custom_domains',  '{"enabled": false}'),
  ('growth',      'max_instructors', '{"limit": 10}'),
  ('growth',      'max_students',    '{"limit": 500}'),
  ('growth',      'max_courses',     '{"limit": 50}'),
  ('growth',      'storage_mb',      '{"limit": 20000}'),
  ('growth',      'coding_labs',     '{"enabled": true}'),
  ('growth',      'custom_branding', '{"enabled": true}'),
  ('growth',      'custom_domains',  '{"enabled": false}'),
  ('institution', 'max_instructors', '{"limit": 200}'),
  ('institution', 'max_students',    '{"limit": 10000}'),
  ('institution', 'max_courses',     '{"limit": 1000}'),
  ('institution', 'storage_mb',      '{"limit": 200000}'),
  ('institution', 'coding_labs',     '{"enabled": true}'),
  ('institution', 'custom_branding', '{"enabled": true}'),
  ('institution', 'custom_domains',  '{"enabled": true}')
) as e(plan_key, key, value) on e.plan_key = p.key;

-- The official Tech Village LMS: the platform's own managed learning environment.
insert into public.organisations (name, workspace_name, slug, org_type, description, is_platform_tenant)
values ('Tech Village', 'Tech Village', 'tech-village', 'training_academy',
        'The official Tech Village learning platform.', true);
insert into public.subscriptions (org_id, plan_id, status)
select o.id, p.id, 'active'
from public.organisations o, public.plans p
where o.is_platform_tenant and p.key = 'institution';

-- =====================================================================
-- RPCs called by the app
-- =====================================================================

-- Flow A: join the official Tech Village LMS as a learner (idempotent).
create or replace function public.join_tech_village()
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_org uuid;
begin
  if v_uid is null then
    raise exception 'Sign in to join Tech Village' using errcode = '28000';
  end if;
  select id into v_org from public.organisations where is_platform_tenant;
  if v_org is null then
    raise exception 'Tech Village is not set up yet';
  end if;
  insert into public.memberships (org_id, user_id, role_id)
  values (v_org, v_uid, public.system_role_id('student'))
  on conflict (org_id, user_id) do nothing;
  return v_org;
end $$;

-- Flow B: create an independent customer workspace. The caller becomes its owner.
create or replace function public.create_workspace(
  p_name text,
  p_workspace_name text,
  p_slug text,
  p_org_type public.org_type,
  p_plan_key text,
  p_description text default null,
  p_country text default null,
  p_contact_email text default null,
  p_contact_phone text default null,
  p_website text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_org uuid;
  v_plan public.plans;
  v_slug text := lower(trim(p_slug));
begin
  if v_uid is null then
    raise exception 'Sign in to create a workspace' using errcode = '28000';
  end if;
  if v_slug in ('app','www','admin','api','auth','login','signup','register','support','help',
                'billing','mail','static','assets','learn','hub','techvillage','tech-village') then
    raise exception 'That workspace address is reserved';
  end if;
  -- One independent workspace per customer.
  if exists (select 1 from public.organisations where created_by = v_uid and not is_platform_tenant) then
    raise exception 'You already own a workspace';
  end if;

  select * into v_plan from public.plans where key = p_plan_key and is_active;
  if not found then
    raise exception 'Unknown plan';
  end if;

  insert into public.organisations
    (name, workspace_name, slug, org_type, description, country,
     contact_email, contact_phone, website, created_by)
  values
    (trim(p_name), trim(p_workspace_name), v_slug, p_org_type, nullif(trim(p_description), ''),
     nullif(trim(p_country), ''), nullif(trim(p_contact_email), ''),
     nullif(trim(p_contact_phone), ''), nullif(trim(p_website), ''), v_uid)
  returning id into v_org;

  insert into public.memberships (org_id, user_id, role_id)
  values (v_org, v_uid, public.owner_role_id());

  insert into public.subscriptions (org_id, plan_id, status, trial_ends_at)
  values (
    v_org, v_plan.id,
    case when v_plan.trial_days > 0 then 'trialing'::public.subscription_status else 'active' end,
    case when v_plan.trial_days > 0 then now() + make_interval(days => v_plan.trial_days) end
  );

  perform public.log_audit(v_org, 'workspace.created', 'organisation', v_org::text,
                           jsonb_build_object('plan', p_plan_key, 'org_type', p_org_type));
  return v_org;
exception when unique_violation then
  raise exception 'That workspace address is already taken';
end $$;

-- Everything the signed-in user belongs to: the official LMS and/or customer workspaces.
-- Suspended workspaces are included so the UI can explain why they are locked.
create or replace function public.my_workspaces()
returns table (
  org_id uuid, name text, workspace_name text, slug text, org_type public.org_type,
  status public.org_status, is_platform_tenant boolean, logo_url text,
  role_key text, role_name text
) language sql stable security definer set search_path = '' as $$
  select o.id, o.name, o.workspace_name, o.slug, o.org_type, o.status,
         o.is_platform_tenant, o.logo_url, r.key, r.name
  from public.memberships m
  join public.organisations o on o.id = m.org_id
  join public.roles r on r.id = m.role_id
  where auth.uid() is not null
    and m.user_id = auth.uid()
    and m.status = 'active'
  order by o.is_platform_tenant desc, o.name;
$$;

-- Permission keys held in a workspace. For UI only: the database re-checks every action.
create or replace function public.my_permissions(p_org uuid)
returns text[] language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(distinct rp.permission_key), '{}')
  from public.memberships m
  join public.organisations o on o.id = m.org_id
  join public.role_permissions rp on rp.role_id = m.role_id
  where m.org_id = p_org
    and o.status = 'active'
    and m.user_id = auth.uid()
    and m.status = 'active';
$$;

-- ---------- Platform admin functions (customer workspaces only) ----------
-- Returns nothing for non-admins. Counts only, never student or course data.
create or replace function public.admin_list_workspaces()
returns table (
  org_id uuid, name text, workspace_name text, slug text, org_type public.org_type,
  status public.org_status, created_at timestamptz, plan_name text,
  subscription_status public.subscription_status, member_count bigint
) language sql stable security definer set search_path = '' as $$
  select o.id, o.name, o.workspace_name, o.slug, o.org_type, o.status, o.created_at,
         p.name, s.status,
         (select count(*) from public.memberships m where m.org_id = o.id)
  from public.organisations o
  left join public.subscriptions s on s.org_id = o.id
  left join public.plans p on p.id = s.plan_id
  where public.is_platform_admin() and not o.is_platform_tenant
  order by o.created_at desc;
$$;

create or replace function public.admin_set_workspace_status(p_org uuid, p_status public.org_status)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrators only' using errcode = '42501';
  end if;
  if exists (select 1 from public.organisations where id = p_org and is_platform_tenant) then
    raise exception 'The official Tech Village LMS cannot be suspended';
  end if;
  update public.organisations set status = p_status where id = p_org;
  if not found then
    raise exception 'Workspace not found';
  end if;
  perform public.log_audit(p_org, 'workspace.status_changed', 'organisation', p_org::text,
                           jsonb_build_object('status', p_status));
end $$;

-- Function execution: signed-in users only.
revoke all on function public.join_tech_village() from public, anon;
revoke all on function public.create_workspace(text, text, text, public.org_type, text, text, text, text, text, text) from public, anon;
revoke all on function public.my_workspaces() from public, anon;
revoke all on function public.my_permissions(uuid) from public, anon;
revoke all on function public.admin_list_workspaces() from public, anon;
revoke all on function public.admin_set_workspace_status(uuid, public.org_status) from public, anon;
grant execute on function public.join_tech_village() to authenticated;
grant execute on function public.create_workspace(text, text, text, public.org_type, text, text, text, text, text, text) to authenticated;
grant execute on function public.my_workspaces() to authenticated;
grant execute on function public.my_permissions(uuid) to authenticated;
grant execute on function public.admin_list_workspaces() to authenticated;
grant execute on function public.admin_set_workspace_status(uuid, public.org_status) to authenticated;

-- =====================================================================
-- Storage: workspace logos
-- Public read. Write only for people holding org.branding in the workspace named by the
-- first folder of the path ("<org-id>/logo.png"). SVG is excluded on purpose (script risk).
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('org-logos', 'org-logos', true, 2097152, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do nothing;

create or replace function public.logo_org_id(p_name text)
returns uuid language sql immutable set search_path = '' as $$
  select case when split_part(p_name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then split_part(p_name, '/', 1)::uuid end;
$$;

create policy org_logos_read on storage.objects for select
  using (bucket_id = 'org-logos');
create policy org_logos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'org-logos' and public.has_permission(public.logo_org_id(name), 'org.branding'));
create policy org_logos_update on storage.objects for update to authenticated
  using (bucket_id = 'org-logos' and public.has_permission(public.logo_org_id(name), 'org.branding'))
  with check (bucket_id = 'org-logos' and public.has_permission(public.logo_org_id(name), 'org.branding'));
create policy org_logos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'org-logos' and public.has_permission(public.logo_org_id(name), 'org.branding'));
