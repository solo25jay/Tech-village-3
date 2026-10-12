import type { EmailMessage, EmailProvider, SendResult } from './types.ts'

export interface ResendConfig {
  apiKey: string
  /** e.g. "Tech Village <hello@mail.yourdomain.com>" on a domain verified in Resend */
  from: string
  fetchImpl?: typeof fetch
  timeoutMs?: number
}

const ENDPOINT = 'https://api.resend.com/emails'

export function createResendProvider(cfg: ResendConfig): EmailProvider {
  const doFetch = cfg.fetchImpl ?? fetch
  const timeoutMs = cfg.timeoutMs ?? 10_000

  return {
    name: 'resend',
    async send(msg: EmailMessage): Promise<SendResult> {
      const headers: Record<string, string> = {
        Authorization: `Bearer ${cfg.apiKey}`,
        'Content-Type': 'application/json',
      }
      if (msg.idempotencyKey) headers['Idempotency-Key'] = msg.idempotencyKey.slice(0, 256)

      const body: Record<string, unknown> = {
        from: cfg.from,
        to: Array.isArray(msg.to) ? msg.to : [msg.to],
        subject: msg.subject,
        html: msg.html,
        text: msg.text,
      }
      if (msg.replyTo) body.reply_to = msg.replyTo

      let res: Response
      try {
        res = await doFetch(ENDPOINT, {
          method: 'POST',
          headers,
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(timeoutMs),
        })
      } catch {
        // Network failure or timeout. Never include the request (it carries the API key) in the error.
        return { ok: false, error: 'Could not reach Resend', retryable: true }
      }

      let payload: { id?: string; message?: string; name?: string } = {}
      try { payload = await res.json() } catch { /* non-JSON body */ }

      if (res.ok) {
        return payload.id
          ? { ok: true, providerId: payload.id }
          : { ok: false, error: 'Resend accepted the request but returned no message id', retryable: false }
      }
      const detail = (payload.message ?? payload.name ?? `HTTP ${res.status}`).toString().slice(0, 300)
      return { ok: false, error: `Resend ${res.status}: ${detail}`, retryable: res.status === 429 || res.status >= 500 }
    },
  }
}
