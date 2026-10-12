export const TOPICS = ['general', 'programme', 'saas', 'partnership'] as const
export type Topic = typeof TOPICS[number]

export interface ContactInput { name: string; email: string; topic: Topic; subject: string; message: string }
export type ContactValidation =
  | { ok: true; data: ContactInput }
  | { ok: true; spam: true }
  | { ok: false; errors: Record<string, string> }

const EMAIL_RE = /^[^\s@<>()[\]\\,;:"]+@[^\s@<>()[\]\\,;:"]+\.[^\s@<>()[\]\\,;:"]{2,}$/

export function validateContact(input: unknown): ContactValidation {
  const raw = (input && typeof input === 'object' ? input : {}) as Record<string, unknown>
  const str = (k: string) => (typeof raw[k] === 'string' ? (raw[k] as string).trim() : '')

  // Honeypot: real people never see or fill this field. Report success so bots learn nothing.
  if (str('website') !== '') return { ok: true, spam: true }

  const errors: Record<string, string> = {}
  const name = str('name')
  const email = str('email').toLowerCase()
  const subject = str('subject')
  const message = str('message')
  const topic = (TOPICS as readonly string[]).includes(str('topic')) ? (str('topic') as Topic) : 'general'

  if (name.length < 2 || name.length > 100) errors.name = 'Enter your name (2 to 100 characters).'
  if (email.length > 254 || !EMAIL_RE.test(email)) errors.email = 'Enter a valid email address.'
  if (subject.length > 150) errors.subject = 'Keep the subject under 150 characters.'
  if (message.length < 10) errors.message = 'Tell us a little more (at least 10 characters).'
  if (message.length > 5000) errors.message = 'Keep the message under 5,000 characters.'

  return Object.keys(errors).length ? { ok: false, errors } : { ok: true, data: { name, email, topic, subject, message } }
}
