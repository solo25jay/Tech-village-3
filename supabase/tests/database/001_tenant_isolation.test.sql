-- Tenant isolation and registration-journey tests for Tech Village V3.1 (pgTAP).
-- Run with:  supabase test db        (requires the Supabase CLI and Docker; use a fresh local database)
--
-- Cast
--   alice  signed up via "Create your own LMS"; owns "Alice Academy" (institution plan)
--   bob    signed up via "Create your own LMS"; owns "Bob Co" (starter plan)
--   carol  instructor in Alice Academy
--   dave   student in Alice Academy
--   erin   signed up via "Join Tech Village": becomes a student of the official LMS automatically
--   frank  signed up via "Create your own LMS" but has not created a workspace yet
--   pat    platform admin
--
-- Users are simulated by setting JWT claims and switching to the `authenticated` role, so RLS,
-- column grants and function grants are all exercised for real.

begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- ---------- helpers ----------
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

-- ---------- fixtures (privileged role) ----------
insert into auth.users (id, email, raw_user_meta_data) values
  ('a1111111-1111-1111-1111-111111111111', 'alice@test.dev', '{"full_name":"Alice","signup_intent":"workspace"}'),
  ('b2222222-2222-2222-2222-222222222222', 'bob@test.dev',   '{"full_name":"Bob","signup_intent":"workspace"}'),
  ('c3333333-3333-3333-3333-333333333333', 'carol@test.dev', '{"full_name":"Carol"}'),
  ('d4444444-4444-4444-4444-444444444444', 'dave@test.dev',  '{"full_name":"Dave"}'),
  ('e5555555-5555-5555-5555-555555555555', 'erin@test.dev',  '{"full_name":"Erin","signup_intent":"learner"}'),
  ('f6666666-6666-6666-6666-666666666666', 'frank@test.dev', '{"full_name":"Frank","signup_intent":"workspace"}'),
  ('99999999-9999-9999-9999-999999999999', 'pat@test.dev',   '{"full_name":"Pat"}');
insert into public.platform_admins (user_id) values ('99999999-9999-9999-9999-999999999999');
do $$ begin
  perform set_config('tv.official', (select id::text from public.organisations where is_platform_tenant), false);
end $$;

select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
do $$ begin
  perform set_config('tv.org_a', public.create_workspace(
    'Alice Academy', 'Alice Academy', 'alice-academy', 'training_academy', 'institution',
    'Coding for everyone', 'NG', 'hello@alice.test', '+2348000000000', 'https://alice.test')::text, false);
end $$;

reset role;
select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('tv.org_b', public.create_workspace('Bob Co', 'Bob Co', 'bob-co', 'corporate_training', 'starter')::text, false);
end $$;

-- carol and dave join Alice Academy (the invitation flow arrives in a later phase)
reset role;
insert into public.memberships (org_id, user_id, role_id) values
  (current_setting('tv.org_a')::uuid, 'c3333333-3333-3333-3333-333333333333', public.system_role_id('instructor')),
  (current_setting('tv.org_a')::uuid, 'd4444444-4444-4444-4444-444444444444', public.system_role_id('student'));

-- =====================================================================
-- 1. Model shape: one official LMS, no sub-accounts
-- =====================================================================
reset role;
select is((select count(*) from public.organisations where is_platform_tenant), 1::bigint, 'there is exactly one official Tech Village LMS');
select is((select slug from public.organisations where is_platform_tenant), 'tech-village', 'the official LMS is seeded by the migration');
select hasnt_column('public', 'organisations', 'parent_id', 'organisations cannot be nested (no parent_id)');
select ok(to_regprocedure('public.create_sub_account(uuid,text,text)') is null, 'there is no create_sub_account function');
select throws_ok($q$insert into public.organisations (name, workspace_name, slug, is_platform_tenant) values ('Second','Second','second-official', true)$q$,
                 '23505', null, 'a second official LMS cannot exist');

-- =====================================================================
-- 2. The two registration journeys
-- =====================================================================
reset role;
select is((select signup_intent from public.profiles where id = 'e5555555-5555-5555-5555-555555555555'), 'learner', 'learner sign-up is recorded on the profile');
select is((select signup_intent from public.profiles where id = 'a1111111-1111-1111-1111-111111111111'), 'workspace', 'workspace sign-up is recorded on the profile');
select is((select r.key from public.memberships m join public.roles r on r.id = m.role_id
           where m.user_id = 'e5555555-5555-5555-5555-555555555555' and m.org_id = current_setting('tv.official')::uuid),
          'student', 'Join Tech Village makes the person a student of the official LMS');
select is((select count(*) from public.memberships where org_id = current_setting('tv.official')::uuid
           and user_id in ('a1111111-1111-1111-1111-111111111111','b2222222-2222-2222-2222-222222222222','f6666666-6666-6666-6666-666666666666')),
          0::bigint, 'Create-your-own-LMS sign-ups are NOT enrolled in the official LMS');
select is((select count(*) from public.organisations where created_by = 'e5555555-5555-5555-5555-555555555555'), 0::bigint, 'a learner never gets a workspace automatically');
select is((select count(*) from public.memberships where user_id = 'f6666666-6666-6666-6666-666666666666'), 0::bigint, 'a workspace sign-up has no membership until setup is finished');
select is((select r.key from public.memberships m join public.roles r on r.id = m.role_id where m.org_id = current_setting('tv.org_a')::uuid and m.user_id = 'a1111111-1111-1111-1111-111111111111'),
          'owner', 'the registering user becomes the workspace owner');

-- =====================================================================
-- 3. Visibility of organisations
-- =====================================================================
select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select is((select count(*) from public.organisations), 1::bigint, 'alice sees only her own workspace');
select is((select count(*) from public.organisations where slug in ('bob-co', 'tech-village')), 0::bigint, 'alice cannot see bob''s workspace or the official LMS');

reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select is((select count(*) from public.organisations), 1::bigint, 'bob sees only his own workspace');
select is((select count(*) from public.organisations where slug = 'alice-academy'), 0::bigint, 'bob cannot see alice''s workspace');

reset role; select pg_temp.act_as('c3333333-3333-3333-3333-333333333333');
select is((select slug from public.organisations), 'alice-academy', 'carol (instructor) sees the workspace she belongs to, and only that');

reset role; select pg_temp.act_as('e5555555-5555-5555-5555-555555555555');
select is((select slug from public.organisations), 'tech-village', 'erin (learner) sees only the official LMS');

reset role; select pg_temp.act_as('f6666666-6666-6666-6666-666666666666');
select is((select count(*) from public.organisations), 0::bigint, 'frank sees nothing until he joins or creates something');

-- =====================================================================
-- 4. Memberships
-- =====================================================================
reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select is((select count(*) from public.memberships), 3::bigint, 'alice sees the three members of her workspace');
select is((select count(*) from public.memberships where user_id = 'e5555555-5555-5555-5555-555555555555'), 0::bigint, 'alice cannot see membership of the official LMS');
select throws_ok($q$update public.memberships set user_id = 'f6666666-6666-6666-6666-666666666666' where user_id = 'd4444444-4444-4444-4444-444444444444'$q$,
                 '42501', null, 'a membership cannot be re-pointed at another user (column grant)');
select throws_ok(format($q$insert into public.memberships (org_id, user_id, role_id) values (%L::uuid, 'f6666666-6666-6666-6666-666666666666'::uuid, public.owner_role_id())$q$, current_setting('tv.org_a')),
                 '42501', null, 'even an owner cannot mint another owner through the API');

reset role; select pg_temp.act_as('d4444444-4444-4444-4444-444444444444');
select is((select count(*) from public.memberships), 1::bigint, 'a student sees only their own membership');
select throws_ok(format($q$insert into public.memberships (org_id, user_id, role_id) values (%L::uuid, 'd4444444-4444-4444-4444-444444444444'::uuid, public.system_role_id('admin'))$q$, current_setting('tv.org_a')),
                 '42501', null, 'a student cannot promote themselves');

reset role; select pg_temp.act_as('c3333333-3333-3333-3333-333333333333');
select is((select count(*) from public.memberships), 1::bigint, 'an instructor without members.manage sees only their own membership');
select throws_ok(format($q$insert into public.memberships (org_id, user_id, role_id) values (%L::uuid, 'f6666666-6666-6666-6666-666666666666'::uuid, public.system_role_id('student'))$q$, current_setting('tv.org_a')),
                 '42501', null, 'an instructor cannot add members');

reset role; select pg_temp.act_as('e5555555-5555-5555-5555-555555555555');
select throws_ok(format($q$insert into public.memberships (org_id, user_id, role_id) values (%L::uuid, 'f6666666-6666-6666-6666-666666666666'::uuid, public.system_role_id('student'))$q$, current_setting('tv.official')),
                 '42501', null, 'a learner cannot add people to the official LMS');
select is((select count(*) from public.memberships), 1::bigint, 'a learner sees only their own membership');

-- =====================================================================
-- 5. Updating organisations
-- =====================================================================
reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select lives_ok(format($q$update public.organisations set name = 'Hacked' where id = %L$q$, current_setting('tv.org_a')), 'bob''s update against alice''s workspace is silently filtered');
reset role;
select is((select name from public.organisations where id = current_setting('tv.org_a')::uuid), 'Alice Academy', 'alice''s workspace is unchanged after bob''s attempt');

select pg_temp.act_as('c3333333-3333-3333-3333-333333333333');
select lives_ok($q$update public.organisations set name = 'Instructor Edit' where slug = 'alice-academy'$q$, 'an instructor''s edit is silently filtered (no org.manage)');
reset role;
select is((select name from public.organisations where id = current_setting('tv.org_a')::uuid), 'Alice Academy', 'workspace unchanged after the instructor''s attempt');

select pg_temp.act_as('e5555555-5555-5555-5555-555555555555');
select lives_ok($q$update public.organisations set name = 'Learner Edit' where is_platform_tenant$q$, 'a learner''s edit of the official LMS is silently filtered');
reset role;
select is((select name from public.organisations where is_platform_tenant), 'Tech Village', 'the official LMS is unchanged after the learner''s attempt');

select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select lives_ok($q$update public.organisations set name = 'Alice Academy Ltd', description = 'Updated' where slug = 'alice-academy'$q$, 'the owner can edit organisation details');
select throws_ok($q$update public.organisations set website = 'ftp://nope' where slug = 'alice-academy'$q$, '23514', null, 'an invalid website is rejected by the table constraint');
select throws_ok($q$update public.organisations set contact_email = 'not-an-email' where slug = 'alice-academy'$q$, '23514', null, 'an invalid contact email is rejected');
select throws_ok($q$update public.organisations set status = 'suspended' where slug = 'alice-academy'$q$, '42501', null, 'an owner cannot change their own workspace status (column grant)');
select throws_ok($q$update public.organisations set is_platform_tenant = true where slug = 'alice-academy'$q$, '42501', null, 'an owner cannot mark their workspace as the official LMS');
select throws_ok($q$update public.organisations set slug = 'hijack' where slug = 'alice-academy'$q$, '42501', null, 'the workspace address cannot be changed');
select throws_ok($q$delete from public.organisations where slug = 'alice-academy'$q$, '42501', null, 'owners cannot delete their workspace directly');
select throws_ok($q$insert into public.organisations (name, workspace_name, slug) values ('Sneaky','Sneaky','sneaky')$q$, '42501', null, 'clients cannot insert organisations directly');

-- =====================================================================
-- 6. Workspace creation rules
-- =====================================================================
reset role; select pg_temp.act_as('f6666666-6666-6666-6666-666666666666');
select throws_ok($q$select public.create_workspace('X','X Co','x-co','banana','starter')$q$, '22P02', null, 'an unknown organisation type is rejected');
select throws_ok($q$select public.create_workspace('Taken Co','Taken','alice-academy','other','starter')$q$, 'P0001', 'That workspace address is already taken', 'a duplicate workspace address is rejected');
select throws_ok($q$select public.create_workspace('Admin Co','Admin','admin','other','starter')$q$, 'P0001', 'That workspace address is reserved', 'reserved addresses are rejected');
select throws_ok($q$select public.create_workspace('Official','Official','tech-village','other','starter')$q$, 'P0001', 'That workspace address is reserved', 'nobody can take the official LMS address');
select throws_ok($q$select public.create_workspace('Bad Co','Bad','Bad_Slug!','other','starter')$q$, '23514', null, 'invalid address characters are rejected');
select throws_ok($q$select public.create_workspace('Plan Co','Plan','plan-co','other','nonexistent')$q$, 'P0001', 'Unknown plan', 'an unknown plan is rejected');
select throws_ok($q$select public.create_workspace('Mail Co','Mail','mail-co','other','starter','d','NG','not-an-email')$q$, '23514', null, 'an invalid contact email is rejected at creation');

select lives_ok($q$select set_config('tv.org_f', public.create_workspace('Frank Tutoring','Frank Tutoring','frank-tutoring','independent_instructor','starter')::text, false)$q$,
                'frank can finish creating his workspace');
select is((select count(*) from public.organisations), 1::bigint, 'after creating a workspace frank sees exactly that workspace');
select is((select r.key from public.my_workspaces() w join public.roles r on r.key = w.role_key and r.org_id is null), 'owner', 'frank is the owner of his new workspace');
select is((select is_platform_tenant from public.organisations), false, 'a customer workspace is never the platform tenant');

reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select throws_ok($q$select public.create_workspace('Second Co','Second','second-co','other','starter')$q$, 'P0001', 'You already own a workspace', 'a customer cannot create a second workspace');

-- =====================================================================
-- 7. Joining Tech Village is separate from owning a workspace
-- =====================================================================
reset role; select pg_temp.act_as('f6666666-6666-6666-6666-666666666666');
select lives_ok($q$select public.join_tech_village()$q$, 'a workspace owner can also join Tech Village as a learner');
select lives_ok($q$select public.join_tech_village()$q$, 'joining twice is harmless');
select is((select count(*) from public.memberships), 2::bigint, 'frank now has exactly two memberships: his workspace and the official LMS');
select is((select r.key from public.my_workspaces() w join public.roles r on r.key = w.role_key and r.org_id is null where w.is_platform_tenant), 'student', 'in the official LMS frank is a student, not an admin');
select is((select r.key from public.my_workspaces() w join public.roles r on r.key = w.role_key and r.org_id is null where not w.is_platform_tenant), 'owner', 'his workspace ownership is unchanged');

-- =====================================================================
-- 8. Billing, entitlements and audit (belong to the workspace)
-- =====================================================================
reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select is((select count(*) from public.subscriptions), 1::bigint, 'alice sees her workspace subscription');
select is((select status::text from public.subscriptions), 'trialing', 'the institution plan starts as a free trial');
select is(public.get_entitlement(current_setting('tv.org_a')::uuid, 'max_students') ->> 'limit', '10000', 'entitlements resolve from the workspace plan');
select ok((select count(*) from public.audit_logs) >= 1, 'alice sees audit entries for her workspace');
select throws_ok($q$insert into public.subscriptions (org_id, plan_id) select id, (select id from public.plans limit 1) from public.organisations limit 1$q$, '42501', null, 'clients cannot write subscriptions');
select throws_ok($q$insert into public.audit_logs (action) values ('forged')$q$, '42501', null, 'clients cannot forge audit entries');

reset role; select pg_temp.act_as('c3333333-3333-3333-3333-333333333333');
select is((select count(*) from public.subscriptions), 0::bigint, 'an instructor cannot see billing');
select is((select count(*) from public.audit_logs), 0::bigint, 'an instructor cannot see the audit log');

reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select is((select count(*) from public.subscriptions), 1::bigint, 'bob sees only his own subscription');
select is((select status::text from public.subscriptions), 'active', 'the free starter plan is active immediately');
select is((select count(*) from public.audit_logs where org_id = current_setting('tv.org_a')::uuid), 0::bigint, 'bob cannot read alice''s audit log');

-- =====================================================================
-- 9. Roles and permissions
-- =====================================================================
reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select is((select count(*) from public.roles where org_id is null), 6::bigint, 'the six system roles are visible to signed-in users');
select lives_ok($q$update public.roles set name = 'Pwned' where org_id is null$q$, 'an edit of system roles is silently filtered');
reset role;
select is((select count(*) from public.roles where name = 'Pwned'), 0::bigint, 'system roles are unchanged after the attempt');

select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select lives_ok(format($q$insert into public.roles (org_id, key, name) values (%L, 'tutor_lead', 'Tutor lead')$q$, current_setting('tv.org_b')), 'bob can create a custom role in his own workspace');
select throws_ok(format($q$insert into public.roles (org_id, key, name) values (%L, 'sneaky', 'Sneaky')$q$, current_setting('tv.org_a')), '42501', null, 'bob cannot create a custom role in alice''s workspace');

reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select is((select count(*) from public.roles where key = 'tutor_lead'), 0::bigint, 'bob''s custom role is invisible to alice');
select ok(public.has_permission(current_setting('tv.org_a')::uuid, 'billing.manage'), 'the owner holds billing.manage');

reset role; select pg_temp.act_as('c3333333-3333-3333-3333-333333333333');
select ok(public.has_permission(current_setting('tv.org_a')::uuid, 'courses.create'), 'an instructor can create courses');
select ok(not public.has_permission(current_setting('tv.org_a')::uuid, 'org.manage'), 'an instructor cannot manage the organisation');
select ok(not public.has_org_access(current_setting('tv.org_b')::uuid), 'an instructor has no access to another workspace');
select ok(not ('org.manage' = any (public.my_permissions(current_setting('tv.org_a')::uuid))), 'my_permissions agrees with has_permission');

-- =====================================================================
-- 10. Switcher functions
-- =====================================================================
reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select is((select count(*) from public.my_workspaces()), 1::bigint, 'alice''s list contains only her workspace');
select ok('billing.manage' = any (public.my_permissions(current_setting('tv.org_a')::uuid)), 'the owner''s permissions include billing.manage');
select is(public.my_permissions(current_setting('tv.org_b')::uuid), '{}'::text[], 'alice holds no permissions in bob''s workspace');

reset role; select pg_temp.act_as('e5555555-5555-5555-5555-555555555555');
select ok((select is_platform_tenant from public.my_workspaces()), 'erin''s only membership is the official LMS');

-- =====================================================================
-- 11. Platform admin: manages workspaces, never reads their data
-- =====================================================================
reset role; select pg_temp.act_as('99999999-9999-9999-9999-999999999999');
select is((select count(*) from public.admin_list_workspaces()), 3::bigint, 'the platform admin lists the three customer workspaces');
select is((select count(*) from public.admin_list_workspaces() where slug = 'tech-village'), 0::bigint, 'the official LMS is not listed as a customer');
select ok(not public.has_org_access(current_setting('tv.org_a')::uuid), 'a platform admin gets no tenant-data access by default');
select is((select count(*) from public.subscriptions), 4::bigint, 'the platform admin can see every subscription for billing');
select throws_ok($q$select count(*) from public.platform_admins$q$, '42501', null, 'even platform admins cannot read platform_admins through the API');
select throws_ok($q$insert into public.platform_admins (user_id) values ('b2222222-2222-2222-2222-222222222222')$q$, '42501', null, 'nobody can grant platform admin through the API');
select throws_ok($q$select public.admin_set_workspace_status(public.system_role_id('owner'), 'suspended')$q$, 'P0001', 'Workspace not found', 'suspending an unknown workspace fails cleanly');
select throws_ok(format($q$select public.admin_set_workspace_status(%L::uuid, 'suspended')$q$, current_setting('tv.official')), 'P0001', 'The official Tech Village LMS cannot be suspended', 'the official LMS cannot be suspended');

reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select is((select count(*) from public.admin_list_workspaces()), 0::bigint, 'a customer owner sees no platform listing');
select throws_ok(format($q$select public.admin_set_workspace_status(%L::uuid, 'suspended')$q$, current_setting('tv.org_b')), '42501', null, 'a customer cannot suspend another workspace');

reset role; select pg_temp.act_as('99999999-9999-9999-9999-999999999999');
select lives_ok(format($q$select public.admin_set_workspace_status(%L::uuid, 'suspended')$q$, current_setting('tv.org_b')), 'the platform admin can suspend a workspace');

reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select ok(not public.has_org_access(current_setting('tv.org_b')::uuid), 'members of a suspended workspace lose data access');
select is((select count(*) from public.organisations), 0::bigint, 'a suspended workspace is hidden from its own members');
select is((select status::text from public.my_workspaces()), 'suspended', 'the switcher still reports the suspended state so the UI can explain it');
select is(public.my_permissions(current_setting('tv.org_b')::uuid), '{}'::text[], 'a suspended workspace grants no permissions');

reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select ok(public.has_org_access(current_setting('tv.org_a')::uuid), 'other workspaces are unaffected by the suspension');

reset role; select pg_temp.act_as('99999999-9999-9999-9999-999999999999');
select lives_ok(format($q$select public.admin_set_workspace_status(%L::uuid, 'active')$q$, current_setting('tv.org_b')), 'the platform admin can reactivate it');
select is((select count(*) from public.audit_logs where action = 'workspace.status_changed'), 2::bigint, 'both status changes were audited');

reset role; select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select ok(public.has_org_access(current_setting('tv.org_b')::uuid), 'access is restored after reactivation');

-- =====================================================================
-- 12. Owners can add staff and students to their own workspace
-- =====================================================================
reset role; select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select lives_ok(format($q$insert into public.memberships (org_id, user_id, role_id) values (%L::uuid, 'f6666666-6666-6666-6666-666666666666'::uuid, public.system_role_id('instructor'))$q$, current_setting('tv.org_a')),
                'an owner can add a member with a non-owner role');
reset role; select pg_temp.act_as('f6666666-6666-6666-6666-666666666666');
select is((select count(*) from public.my_workspaces()), 3::bigint, 'frank now sees the official LMS, his workspace and Alice Academy');
select is((select count(*) from public.my_workspaces() where not is_platform_tenant), 2::bigint, 'one person can belong to several customer workspaces');

-- =====================================================================
-- 13. Visitors who are not signed in
-- =====================================================================
reset role; select pg_temp.act_as_anon();
select is((select count(*) from public.plans), 3::bigint, 'visitors can read the public plan catalogue');
select ok((select count(*) from public.plan_entitlements) > 0, 'visitors can read plan entitlements for the pricing page');
select throws_ok($q$select count(*) from public.organisations$q$, '42501', null, 'visitors cannot read organisations');
select throws_ok($q$select count(*) from public.memberships$q$, '42501', null, 'visitors cannot read memberships');
select throws_ok($q$select public.create_workspace('Anon','Anon','anon-ws','other','starter')$q$, '42501', null, 'visitors cannot create workspaces');
select throws_ok($q$select public.join_tech_village()$q$, '42501', null, 'visitors cannot join Tech Village without an account');
select throws_ok($q$select * from public.admin_list_workspaces()$q$, '42501', null, 'visitors cannot call platform admin functions');
select throws_ok($q$select count(*) from public.platform_admins$q$, '42501', null, 'visitors cannot read platform_admins');

select * from finish();
rollback;
