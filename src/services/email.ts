import { supabase } from '@/lib/supabase'

export interface ContactPayload {
  name: string; email: string; topic: string; subject: string; message: string
  /** Honeypot. Real visitors never fill this in. */
  website: string
}

/** Pulls a readable message out of a failed Edge Function response. */
async function readFunctionError(error: unknown, fallback: string): Promise<{ message: string; fields?: Record<string, string> }> {
  const ctx = (error as { context?: Response } | null)?.context
  if (ctx && typeof ctx.json === 'function') {
    try {
      const body = await ctx.json() as { error?: string; fields?: Record<string, string> }
      return { message: body.error ?? fallback, fields: body.fields }
    } catch { /* not JSON */ }
  }
  return { message: fallback }
}

export class ContactError extends Error {
  fields?: Record<string, string>
  constructor(message: string, fields?: Record<string, string>) { super(message); this.fields = fields }
}

export async function sendContactMessage(payload: ContactPayload): Promise<void> {
  const { error } = await supabase.functions.invoke('contact', { body: payload })
  if (error) {
    const { message, fields } = await readFunctionError(error, 'We could not send your message. Please try again in a moment.')
    throw new ContactError(message, fields)
  }
}

/** Fire-and-forget. A failed welcome email must never get in the way of creating a workspace. */
export async function sendWorkspaceWelcome(orgId: string): Promise<void> {
  try {
    const { error } = await supabase.functions.invoke('send-email', { body: { template: 'workspace_welcome', org_id: orgId } })
    if (error) console.warn('Welcome email was not sent')
  } catch { console.warn('Welcome email was not sent') }
}
