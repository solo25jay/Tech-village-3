// Public contact form endpoint. Deploy with: supabase functions deploy contact --no-verify-jwt
// (visitors are not signed in, so there is no JWT to verify; abuse is limited below).
import { createClient } from 'npm:@supabase/supabase-js@2'
import { corsHeaders, json } from '../_shared/cors.ts'
import { validateContact } from '../_shared/contact.ts'
import { createEmailProvider } from '../_shared/email/index.ts'
import { renderContactNotification, renderContactReceipt } from '../_shared/email/templates.ts'
import { deliver } from '../_shared/deliver.ts'

const MAX_PER_IP_PER_HOUR = 5
const MAX_PER_EMAIL_PER_HOUR = 3

async function sha256(input: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input))
  return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('')
}

Deno.serve(async (req) => {
  const siteUrl = Deno.env.get('SITE_URL') ?? ''
  const cors = corsHeaders(req, siteUrl)
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405, cors)

  let body: unknown
  try { body = await req.json() } catch { return json({ error: 'Invalid request' }, 400, cors) }

  const v = validateContact(body)
  if (!v.ok) return json({ error: 'Please check the form', fields: v.errors }, 422, cors)
  if ('spam' in v) return json({ status: 'received' }, 200, cors) // honeypot tripped: pretend success

  const inbox = Deno.env.get('CONTACT_INBOX')
  if (!inbox) {
    console.error('CONTACT_INBOX is not set')
    return json({ error: 'Contact is not configured yet. Please try again later.' }, 503, cors)
  }

  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  })

  // Rate limit by hashed IP and by email. Only hashes are stored, never raw IPs.
  const ip = (req.headers.get('x-forwarded-for') ?? '').split(',')[0].trim() || 'unknown'
  const ipHash = await sha256(`${Deno.env.get('CONTACT_HASH_SALT') ?? ''}|${ip}`)
  const since = new Date(Date.now() - 3600_000).toISOString()
  const [byIp, byEmail] = await Promise.all([
    db.from('contact_messages').select('id', { count: 'exact', head: true }).eq('ip_hash', ipHash).gte('created_at', since),
    db.from('contact_messages').select('id', { count: 'exact', head: true }).eq('email', v.data.email).gte('created_at', since),
  ])
  if ((byIp.count ?? 0) >= MAX_PER_IP_PER_HOUR || (byEmail.count ?? 0) >= MAX_PER_EMAIL_PER_HOUR) {
    return json({ error: 'Too many messages. Please try again in an hour.' }, 429, cors)
  }

  const { error: saveError } = await db.from('contact_messages').insert({ ...v.data, ip_hash: ipHash })
  if (saveError) {
    console.error('contact save failed', saveError.code)
    return json({ error: 'Could not save your message. Please try again.' }, 500, cors)
  }

  // The message is safely stored. Email is best effort: a mail failure must not lose the message.
  try {
    const provider = createEmailProvider({
      EMAIL_PROVIDER: Deno.env.get('EMAIL_PROVIDER') ?? undefined,
      RESEND_API_KEY: Deno.env.get('RESEND_API_KEY') ?? undefined,
      EMAIL_FROM: Deno.env.get('EMAIL_FROM') ?? undefined,
    })
    const note = renderContactNotification({ ...v.data, siteUrl })
    await deliver(db, provider, { to: inbox, replyTo: v.data.email, ...note }, { template: 'contact_notification' })
    const receipt = renderContactReceipt({ name: v.data.name, siteUrl })
    await deliver(db, provider, { to: v.data.email, ...receipt }, { template: 'contact_receipt' })
  } catch (e) {
    console.error('contact email failed', (e as Error).message)
  }

  return json({ status: 'received' }, 200, cors)
})
