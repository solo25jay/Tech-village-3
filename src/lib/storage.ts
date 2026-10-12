import { supabase } from '@/lib/supabase'

const ALLOWED = ['image/png', 'image/jpeg', 'image/webp']
const MAX_BYTES = 2 * 1024 * 1024

/** Returns an error message, or null if the file is acceptable. The bucket enforces the same limits server-side. */
export function validateLogo(file: File): string | null {
  if (!ALLOWED.includes(file.type)) return 'Use a PNG, JPEG or WebP image.'
  if (file.size > MAX_BYTES) return 'The logo must be 2 MB or smaller.'
  return null
}

/** Uploads to "<org-id>/logo.<ext>". Storage policy requires org.branding in that workspace. */
export async function uploadOrgLogo(orgId: string, file: File): Promise<string> {
  const problem = validateLogo(file)
  if (problem) throw new Error(problem)
  const ext = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg'
  const path = `${orgId}/logo.${ext}`
  const { error } = await supabase.storage.from('org-logos').upload(path, file, { upsert: true, contentType: file.type })
  if (error) throw error
  const { data } = supabase.storage.from('org-logos').getPublicUrl(path)
  return `${data.publicUrl}?v=${Date.now()}` // cache-bust after replacing a logo
}
