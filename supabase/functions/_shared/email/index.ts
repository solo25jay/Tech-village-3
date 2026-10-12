import type { EmailMessage, EmailProvider } from './types.ts'
import { createResendProvider } from './resend.ts'

export interface EmailEnv {
  EMAIL_PROVIDER?: string
  RESEND_API_KEY?: string
  EMAIL_FROM?: string
}

/** Development-only provider: logs instead of sending. Must be opted into explicitly. */
function createConsoleProvider(): EmailProvider {
  return {
    name: 'console',
    send(msg: EmailMessage) {
      console.log('[email:console]', JSON.stringify({ to: msg.to, subject: msg.subject }))
      return Promise.resolve({ ok: true as const, providerId: `console-${crypto.randomUUID()}` })
    },
  }
}

/**
 * Picks the provider from configuration. Missing configuration is an error, not a silent no-op,
 * so a misconfigured deployment fails loudly instead of pretending to send mail.
 */
export function createEmailProvider(env: EmailEnv): EmailProvider {
  const name = (env.EMAIL_PROVIDER ?? 'resend').toLowerCase()
  if (name === 'console') return createConsoleProvider()
  if (name === 'resend') {
    if (!env.RESEND_API_KEY) throw new Error('RESEND_API_KEY is not set')
    if (!env.EMAIL_FROM) throw new Error('EMAIL_FROM is not set')
    return createResendProvider({ apiKey: env.RESEND_API_KEY, from: env.EMAIL_FROM })
  }
  throw new Error(`Unknown EMAIL_PROVIDER "${name}"`)
}
