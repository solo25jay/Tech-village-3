# Tech Village: Phase 1 foundation (V3.1)

Vue 3 + TypeScript + Vite + Tailwind + Pinia + Vue Router on Vercel, with Supabase (Postgres, Auth, Storage, RLS).

## The model in one paragraph
Tech Village runs **one official LMS** (a seeded organisation, `tech-village`) and hosts **independent customer workspaces**.
Individuals who choose **Join Tech Village** become students of the official LMS. Customers who choose **Create Your Own LMS**
register an organisation and become the owner of one independent workspace. A person can be both. There are no sub-accounts,
campuses or nested workspaces. Each workspace has its own members, settings, branding and subscription.

| Journey | Route | Result |
|---|---|---|
| Sign up chooser | `/signup` | Two clearly separate cards |
| Join Tech Village | `/signup/learner` | Personal account, student of the official LMS, lands on `/learn` |
| Create Your Own LMS | `/signup/lms` | Plan, account, organisation, workspace; owner of a new workspace, lands on `/app` |
| Signed-in router | `/hub` | Sends people to learning, workspace, or lets someone with both choose |
| Platform admin | `/admin` | Lists customer workspaces, suspend/reactivate (counts only, no tenant data) |

## Run it
1. `npm install`
2. Create a Supabase project and apply the migrations in order: `0001_foundation.sql`, `0002_email_and_contact.sql`, `0003_lms_core.sql` (SQL editor, or `supabase db push`).
   If you applied an earlier version of 0001 (it used to include sub-accounts), reset the database first (`supabase db reset` locally, or recreate the project).
3. `cp .env.example .env` and add the project URL and anon key (Project settings > API).
4. In Supabase Auth settings, keep email confirmation on, set the Site URL, and add `http://localhost:5173/**` and your Vercel URL (with `/**`) to the redirect allow-list. Confirmation links land on `/hub`; password resets land on `/reset-password`.
5. `npm run dev`
6. Sign up, then edit the email in `supabase/seed_platform.sql` and run it to become platform admin and owner of the official LMS.

## What is included
- Brand tokens from the logo (light and dark), contrast checked: `docs/brand-tokens.md`
- Public website: home, about, learning paths, pricing (read live from the plans table), contact, per-route SEO titles and descriptions, robots.txt
- Two registration journeys, sign in, password reset, route guards
- Schema and RLS for the model above, plus email delivery history (`email_outbox`) and contact messages
- Email through Resend behind a replaceable provider interface (`supabase/functions/_shared/email/`): contact form with honeypot and rate limiting,
  workspace welcome email (sent once per workspace), delivery history. Setup: `docs/email-setup.md`
- **LMS core (Phase 5):** courses with modules and lessons; each lesson is an ordered list of text and video blocks (YouTube/Vimeo only,
  rebuilt from a validated ID, never an author-typed URL); drafts and publishing; enrolment; per-lesson progress. The same screens serve the
  official LMS (`/learn/courses`) and customer workspaces (`/app/courses`).
- **Team and invitations:** invite people by link with a role, accept only with a verified matching email, single use, 14-day expiry, revoke,
  suspend, change role. Only a hash of the link secret is stored.
- Workspace area: dashboard with a real setup checklist, organisation settings with logo upload. Learner area: dashboard. Platform admin: workspace list with suspend/reactivate.

## Tests
`npm run test:unit` runs 7 tests on the video-link parser (lookalike hosts, credential tricks, injected IDs, DB pattern match).
`npm run test:email` runs 12 unit tests in plain Node (Resend request shape, error handling, key never leaked, template escaping, header-injection protection,
contact validation, outbox logging and de-duplication, pricing formatters). No Supabase needed.

### Database tests
`supabase test db` (needs the Supabase CLI and Docker) runs both files in `supabase/tests/database/`: `001_tenant_isolation` (about 115 checks) and
`002_lms_core` (about 105 checks on courses, content, enrolment gating, progress, plan limits and invitations). It covers both registration journeys, cross-workspace reads and writes, column-level protection, one-workspace-per-customer,
the official LMS, platform-admin separation, suspension, audit, and anonymous access. Use a fresh local database; some counts assume no other data.

## Deploy
Push to GitHub, import the repo in Vercel, add the two `VITE_` variables. `vercel.json` handles SPA routing.

## How course data stays inside one workspace
Every course table carries `org_id`, and child rows are tied to their parent with composite foreign keys such as `(course_id, org_id)`. Even if a client
lies about `org_id`, the database refuses a module, lesson, block, enrolment or progress row that points at another workspace's course.
Lesson content is readable only by people who can edit the course or hold an active enrolment in a published one. Plan limits (`max_courses`,
`max_students`) are enforced by database triggers; the official LMS is exempt.

## Design decisions to review
- **Registration intent.** The sign-up journey is stored in user metadata and copied to `profiles.signup_intent`. Only `learner` has an effect in the database (it adds a student membership to the official LMS), which is safe because that journey is open to everyone anyway.
- **One workspace per customer.** `create_workspace` refuses a second one. Change the check in the function if you later want consultants to own several.
- **Roles.** System roles: owner, administrator, instructor, teaching assistant, student, mentor (official LMS). Finance, content-manager and read-only reporting roles from V3.0 are not seeded; owners can create them as custom roles.
- **Platform admins** can list workspaces and see plan, status and member counts, but `has_org_access()` excludes them, so students and courses stay private unless a future audited support-access feature is added.
- **Suspension** blocks all data access for a workspace's members. They still see a clear "suspended" state.
- **Logos** use a public Storage bucket (`org-logos`, PNG/JPEG/WebP, 2 MB). Only people with `org.branding` in that workspace can write to its folder. SVG is excluded on purpose.
- Plan prices are placeholders in NGN minor units.

## Notes on the public site
- Learning paths in `src/content/programmes.ts` are placeholders. Replace them with your real curriculum.
- The site is a single-page app, so search engines see the titles and descriptions set per route but not server-rendered content. Add pre-rendering later if search ranking matters.
- There are no testimonials or statistics because none exist yet. Add them when you have real ones.

## Known gaps
- Invitation links are copied by hand: no email is sent yet. Sending them needs a new, tightly-scoped template in the email function (the recipient is not the caller, so it needs its own abuse controls).
- Staff can enrol members directly in the database, but there is no screen for it yet; learners enrol themselves.
- Assignments, quizzes, certificates, bulk import, instructor/learner analytics and course pricing are not built.
- Reordering uses up/down buttons rather than drag-and-drop.
- Lesson text is plain text with paragraph breaks (no rich formatting), by design: it is rendered as text, never HTML.
- Payments, email templates, custom domains and everything after Phase 1 are not built.
- Official LMS content (courses, community, mentorship) is not built; the learner dashboard says so plainly.
