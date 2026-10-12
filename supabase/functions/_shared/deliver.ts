import type { EmailMessage, EmailProvider, SendResult } from './email/types.ts'

// Minimal shape of the Supabase client we use, so this module is testable without the SDK.
// deno-lint-ignore no-explicit-any
export type Db = { from: (table: string) => any }

export interface DeliveryMeta { template: string; org_id?: string | null; user_id?: string | null }
export type DeliveryResult = SendResult | { ok: true; deduped: true }

/**
 * Records the attempt in email_outbox (delivery history and failure tracking), sends through the
 * provider, then records the outcome. The outbox row is written first so a crash mid-send
 * still leaves a trace, and a unique index on the welcome email prevents duplicates under races.
 */
export async function deliver(db: Db, provider: EmailProvider, msg: EmailMessage, meta: DeliveryMeta): Promise<DeliveryResult> {
  const to = Array.isArray(msg.to) ? msg.to[0] : msg.to
  const { data: row, error: insertError } = await db.from('email_outbox')
    .insert({
      org_id: meta.org_id ?? null, user_id: meta.user_id ?? null, template: meta.template,
      to_email: to, subject: msg.subject, status: 'queued', provider: provider.name,
    })
    .select('id').single()

  if (insertError) {
    if (insertError.code === '23505') return { ok: true, deduped: true }
    return { ok: false, error: 'Could not record the email', retryable: true }
  }

  const result = await provider.send(msg)
  const patch = result.ok
    ? { status: 'sent', provider_message_id: result.providerId, sent_at: new Date().toISOString() }
    : { status: 'failed', error: result.error }
  await db.from('email_outbox').update(patch).eq('id', row.id)
  return result
}
