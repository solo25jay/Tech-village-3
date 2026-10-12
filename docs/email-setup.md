# Email setup (Resend)

Two separate paths send mail. Set up both.

| Path | Used for | How it connects to Resend |
|---|---|---|
| Supabase Auth emails | Sign-up confirmation, password reset | Custom SMTP in the Supabase dashboard |
| Edge Functions | Contact form, workspace welcome, future notifications | Resend HTTP API with a server-side secret |

The Resend API key is only ever stored as a Supabase secret or SMTP password. It must never be placed in a `VITE_` variable or committed.

## 1. Resend
1. Create a Resend account and add your sending domain (use a subdomain such as `mail.yourdomain.com`).
2. Add the DNS records Resend shows (SPF, DKIM). Wait until the domain shows as verified.
3. Create **two** API keys with sending access: one for the Edge Functions, one for Supabase SMTP. Separate keys can be revoked independently.

## 2. Edge Function secrets
```bash
supabase secrets set \
  RESEND_API_KEY=re_xxxxxxxx \
  EMAIL_FROM="Tech Village <hello@mail.yourdomain.com>" \
  CONTACT_INBOX=you@yourdomain.com \
  SITE_URL=https://your-app.vercel.app \
  CONTACT_HASH_SALT=$(openssl rand -hex 16)
```
`SITE_URL` also sets the allowed browser origin. Use a comma-separated list for several (for example your Vercel URL and `http://localhost:5173` while developing).

## 3. Deploy the functions
```bash
supabase db push                                      # applies migrations 0001 and 0002
supabase functions deploy contact --no-verify-jwt     # public form: visitors have no JWT
supabase functions deploy send-email                  # JWT verification stays on
```
If you maintain `supabase/config.toml`, you can record the first setting there instead:
```toml
[functions.contact]
verify_jwt = false
```

## 4. Supabase Auth emails through Resend
Either use the Resend integration from the Supabase integrations page (it creates the key and fills in SMTP), or set it by hand under **Authentication > SMTP Settings**:
- Host `smtp.resend.com`, port `465`, username `resend`, password = the second API key
- Sender: an address on your verified domain

Then paste the two files in `supabase/templates/` into **Authentication > Email Templates**, and add your site URL, `/hub` and `/reset-password` to **Authentication > URL Configuration > Redirect URLs**. Confirmation links land on `/hub`, which sends learners and workspace owners to the right place.

## 5. Check it works
1. Open the Contact page and send a message. You should receive the notification, and the sender receives a receipt. The message is stored even if email fails.
2. Create a workspace. The owner receives one welcome email.
3. In Supabase, `select * from email_outbox order by created_at desc;` shows each attempt with `sent` or `failed` and the error text.

## Local development
Set `EMAIL_PROVIDER=console` in `supabase/functions/.env` to log emails instead of sending them. The code refuses to send if `RESEND_API_KEY` or `EMAIL_FROM` is missing, so a misconfigured production deploy fails loudly rather than silently dropping mail.

## Replacing Resend later
Add a file in `supabase/functions/_shared/email/` that implements `EmailProvider`, register it in `index.ts`, and set `EMAIL_PROVIDER`. Templates, functions and the outbox do not change.
