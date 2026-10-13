-- Run once in the Supabase SQL editor AFTER you have signed up with your own account.
-- The official Tech Village LMS organisation already exists (created by the migration).
-- This makes you a platform admin and the owner of the official LMS.
insert into public.platform_admins (user_id)
select id from auth.users where email = 'obasogiesolomon0@gmail.com'
on conflict do nothing;

insert into public.memberships (org_id, user_id, role_id)
select o.id, u.id, public.owner_role_id()
from public.organisations o, auth.users u
where o.is_platform_tenant and u.email = 'obasogiesolomon0@gmail.com'
on conflict (org_id, user_id) do update set role_id = excluded.role_id, status = 'active';
