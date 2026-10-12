/** Turn a Supabase/Postgres error into a message a person can act on. */
export function friendlyError(err: unknown): string {
  const e = err as { message?: string; code?: string } | null
  if (!e) return 'Something went wrong. Try again.'
  if (e.code === '42501') {
    // Our functions raise readable sentences; Postgres' own messages are boilerplate.
    const ours = e.message && !/^(permission denied|new row violates)/i.test(e.message)
    return ours ? e.message! : 'You do not have permission to do that.'
  }
  if (e.code === '28000') return 'Sign in and try again.'
  if (e.code === '23505') return 'That value is already in use.'
  if (e.message?.toLowerCase().includes('invalid login')) return 'Email or password is incorrect.'
  if (e.message?.toLowerCase().includes('failed to fetch')) return 'Could not reach the server. Check your connection.'
  return e.message ?? 'Something went wrong. Try again.'
}

export function slugify(input: string): string {
  return input
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40)
    .replace(/-+$/, '')
}
