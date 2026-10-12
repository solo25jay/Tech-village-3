-- Privacy tests for email history and contact messages (pgTAP). Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

create or replace function pg_temp.act_as(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  execute 'set local role authenticated';
end $$;

insert into auth.users (id, email) values
  ('a1111111-1111-1111-1111-111111111111', 'alice@test.dev'),
  ('b2222222-2222-2222-2222-222222222222', 'bob@test.dev'),
  ('e5555555-5555-5555-5555-555555555555', 'pat@test.dev');
insert into public.platform_admins (user_id) values ('e5555555-5555-5555-5555-555555555555');

select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
do $$ begin perform set_config('tv.org_a', public.create_workspace('Alice Academy', 'alice-academy', 'school', 'NG', 'starter')::text, false); end $$;
reset role;
select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
do $$ begin perform set_config('tv.org_b', public.create_workspace('Bob Co', 'bob-co', 'corporate', 'GH', 'starter')::text, false); end $$;

-- rows as the Edge Function (service role) would write them
reset role;
insert into public.email_outbox (org_id, template, to_email, subject, status, provider)
values (current_setting('tv.org_a')::uuid, 'workspace_welcome', 'alice@test.dev', 'Welcome', 'sent', 'resend');
insert into public.contact_messages (name, email, message) values ('Visitor', 'v@test.dev', 'Hello, I have a question.');

-- email_outbox
select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select is((select count(*) from public.email_outbox), 1::bigint, 'owner sees their workspace''s email history');
select throws_ok($q$insert into public.email_outbox (template, to_email, subject, provider) values ('x','y@z.co','s','resend')$q$, '42501', null, 'clients cannot write email history');
select throws_ok($q$update public.email_outbox set status = 'sent'$q$, '42501', null, 'clients cannot edit email history');

reset role;
select pg_temp.act_as('b2222222-2222-2222-2222-222222222222');
select is((select count(*) from public.email_outbox), 0::bigint, 'another tenant cannot see alice''s email history');

reset role;
select throws_ok(format($q$insert into public.email_outbox (org_id, template, to_email, subject, provider) values (%L, 'workspace_welcome', 'alice@test.dev', 'Again', 'resend')$q$, current_setting('tv.org_a')),
                 '23505', null, 'a second welcome email for the same workspace is blocked by the unique index');
select lives_ok(format($q$insert into public.email_outbox (org_id, template, to_email, subject, status, provider) values (%L, 'workspace_welcome', 'bob@test.dev', 'Welcome', 'failed', 'resend')$q$, current_setting('tv.org_b')),
                'a failed welcome attempt can be recorded');
select lives_ok(format($q$insert into public.email_outbox (org_id, template, to_email, subject, status, provider) values (%L, 'workspace_welcome', 'bob@test.dev', 'Welcome retry', 'sent', 'resend')$q$, current_setting('tv.org_b')),
                'a retry after a failed attempt is allowed');

-- contact_messages
select pg_temp.act_as('a1111111-1111-1111-1111-111111111111');
select is((select count(*) from public.contact_messages), 0::bigint, 'tenant owners see none of the visitor contact messages');
reset role;
select pg_temp.act_as('e5555555-5555-5555-5555-555555555555');
select is((select count(*) from public.contact_messages), 1::bigint, 'platform admin can read contact messages');
select lives_ok($q$update public.contact_messages set status = 'read'$q$, 'platform admin can mark a message as read');
select throws_ok($q$update public.contact_messages set message = 'edited message text here'$q$, '42501', null, 'message content cannot be edited');
select throws_ok($q$insert into public.contact_messages (name, email, message) values ('X','x@y.co','Direct insert attempt')$q$, '42501', null, 'nobody can insert contact messages straight through the API');

reset role;
set local role anon;
select throws_ok($q$insert into public.contact_messages (name, email, message) values ('Bot','b@y.co','Anonymous direct insert')$q$, '42501', null, 'visitors must go through the rate-limited function');
select throws_ok($q$select count(*) from public.contact_messages$q$, '42501', null, 'visitors cannot read contact messages');

reset role;
select * from finish();
rollback;
