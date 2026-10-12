-- =====================================================================
-- Tech Village - email delivery history and public contact messages
-- Both tables are written only by Edge Functions using the service role.
-- =====================================================================

create table public.email_outbox (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references public.organisations (id) on delete set null,
  user_id uuid references auth.users (id) on delete set null,
  template text not null,
  to_email text not null,
  subject text not null,
  status text not null default 'queued' check (status in ('queued', 'sent', 'failed')),
  provider text not null,
  provider_message_id text,
  error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
create index email_outbox_org_idx on public.email_outbox (org_id, created_at desc);
create index email_outbox_status_idx on public.email_outbox (status, created_at desc);

-- A workspace gets exactly one welcome email, even if the request is retried or raced.
-- A failed attempt does not block a later retry.
create unique index email_outbox_welcome_once
  on public.email_outbox (org_id, template)
  where template = 'workspace_welcome' and status <> 'failed';

alter table public.email_outbox enable row level security;
create policy email_outbox_select on public.email_outbox for select to authenticated
  using ((org_id is not null and public.has_permission(org_id, 'reports.view')) or public.is_platform_admin());
revoke all on public.email_outbox from anon, authenticated;
grant select on public.email_outbox to authenticated;

create table public.contact_messages (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 100),
  email text not null check (char_length(email) <= 254),
  topic text not null default 'general' check (topic in ('general', 'programme', 'saas', 'partnership')),
  subject text not null default '' check (char_length(subject) <= 150),
  message text not null check (char_length(message) between 10 and 5000),
  status text not null default 'new' check (status in ('new', 'read', 'replied', 'spam')),
  ip_hash text,                       -- salted SHA-256 for rate limiting; the raw IP is never stored
  created_at timestamptz not null default now()
);
create index contact_messages_rate_idx on public.contact_messages (ip_hash, created_at desc);
create index contact_messages_email_idx on public.contact_messages (email, created_at desc);

alter table public.contact_messages enable row level security;
create policy contact_messages_admin_select on public.contact_messages for select to authenticated
  using (public.is_platform_admin());
create policy contact_messages_admin_update on public.contact_messages for update to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());
revoke all on public.contact_messages from anon, authenticated;
grant select on public.contact_messages to authenticated;
grant update (status) on public.contact_messages to authenticated;
