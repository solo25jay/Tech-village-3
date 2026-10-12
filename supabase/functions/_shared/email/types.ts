// Provider-neutral email contracts. Business logic depends on these, never on Resend directly,
// so the provider can be swapped without touching templates, functions or the outbox.

export interface EmailMessage {
  to: string | string[]
  subject: string
  html: string
  text: string
  replyTo?: string
  /** Same key + same payload within the provider's window sends only once. Max 256 chars. */
  idempotencyKey?: string
}

export type SendResult =
  | { ok: true; providerId: string }
  | { ok: false; error: string; retryable: boolean }

export interface EmailProvider {
  readonly name: string
  send(message: EmailMessage): Promise<SendResult>
}
