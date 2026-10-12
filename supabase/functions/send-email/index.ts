// Authenticated transactional email. Deploy with: supabase functions deploy send-email
// (JWT verification stays ON). The caller can only name a template and a workspace.
// The recipient is always the signed-in user's own address, so this cannot be used to spam others.
import { createClient } from 'npm:@supabase/supabase-js@2'
import { corsHeaders, json } from '../_shared/cors.ts'
import { createEmailProvider } from '../_shared/email/index.ts'
import { renderWorkspaceWelcome } from '../_shared/email/templates.ts'
import { deliver } from '../_shared/deliver.ts'

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

Deno.serve(async (req) => {
  const siteUrl = Deno.env.get('SITE_URL') ?? ''
  const cors = corsHeaders(req, siteUrl)
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405, cors)

  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return json({ error: 'Sign in first' }, 401, cors)

  let body: { template?: string; org_id?: string }
  try { body = await req.json() } catch { return json({ error: 'Invalid request' }, 400, cors) }
  if (body.template !== 'workspace_welcome' || !body.org_id || !UUID_RE.test(body.org_id)) {
    return json({ error: 'Unsupported request' }, 400, cors)
  }

  // Act as the caller so their RLS and the server-side workspace list decide what they may do.
  const asUser = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authHeader } }, auth: { persistSession: false },
  })
  const { data: userData, error: userError } = await asUser.auth.getUser()
  if (userError || !userData.user?.email) return json({ error: 'Sign in first' }, 401, cors)
  const user = userData.user

  const { data: spaces, error: spacesError } = await asUser.rpc('my_workspaces')
  if (spacesError) return json({ error: 'Could not verify your workspace' }, 500, cors)
  const space = (spaces as Array<{ org_id: string; workspace_name: string; is_platform_tenant: boolean; role_key: string }> | null)
    ?.find(w => w.org_id === body.org_id)
  if (!space || space.is_platform_tenant || space.role_key !== 'owner') {
    return json({ error: 'Not allowed' }, 403, cors)
  }

  const { data: profile } = await asUser.from('profiles').select('full_name').eq('id', user.id).maybeSingle()

  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  })

  try {
    const provider = createEmailProvider({
      EMAIL_PROVIDER: Deno.env.get('EMAIL_PROVIDER') ?? undefined,
      RESEND_API_KEY: Deno.env.get('RESEND_API_KEY') ?? undefined,
      EMAIL_FROM: Deno.env.get('EMAIL_FROM') ?? undefined,
    })
    const mail = renderWorkspaceWelcome({
      name: profile?.full_name || '', workspaceName: space.workspace_name, appUrl: siteUrl.split(',')[0].trim(), siteUrl: siteUrl.split(',')[0].trim(),
    })
    const result = await deliver(db, provider,
      { to: user.email!, idempotencyKey: `workspace_welcome/${space.org_id}`, ...mail },
      { template: 'workspace_welcome', org_id: space.org_id, user_id: user.id })
    if (!result.ok) return json({ error: 'The email could not be sent' }, 502, cors)
    return json({ status: 'deduped' in result ? 'already_sent' : 'sent' }, 200, cors)
  } catch (e) {
    console.error('send-email failed', (e as Error).message)
    return json({ error: 'Email is not configured yet' }, 503, cors)
  }
})
