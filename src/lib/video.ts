/**
 * Lesson videos are YouTube or Vimeo only. We never embed a URL the author typed: we parse it,
 * extract an ID that matches a strict pattern, and rebuild both the stored (canonical) link and
 * the embed address from that ID. Anything else is rejected. The database enforces the same
 * canonical shapes with a CHECK constraint.
 */
export interface VideoRef {
  provider: 'youtube' | 'vimeo'
  id: string
  canonical: string // what we store
  embed: string     // what we put in the iframe
}

const YOUTUBE_ID = /^[A-Za-z0-9_-]{11}$/
const VIMEO_ID = /^[0-9]{6,12}$/

function youtube(id: string | null | undefined): VideoRef | null {
  if (!id || !YOUTUBE_ID.test(id)) return null
  return {
    provider: 'youtube', id,
    canonical: `https://www.youtube.com/watch?v=${id}`,
    embed: `https://www.youtube-nocookie.com/embed/${id}`,
  }
}

function vimeo(id: string | null | undefined): VideoRef | null {
  if (!id || !VIMEO_ID.test(id)) return null
  return { provider: 'vimeo', id, canonical: `https://vimeo.com/${id}`, embed: `https://player.vimeo.com/video/${id}` }
}

export function parseVideoUrl(input: string): VideoRef | null {
  let u: URL
  try { u = new URL(input.trim()) } catch { return null }
  if (u.protocol !== 'https:' || u.username || u.password || u.port) return null

  const host = u.hostname.toLowerCase()
  const parts = u.pathname.split('/').filter(Boolean)

  if (host === 'youtube.com' || host === 'www.youtube.com' || host === 'm.youtube.com') {
    if (u.pathname === '/watch') return youtube(u.searchParams.get('v'))
    if (parts[0] === 'embed' || parts[0] === 'shorts') return youtube(parts[1])
    return null
  }
  if (host === 'youtu.be') return youtube(parts[0])
  if (host === 'vimeo.com' || host === 'www.vimeo.com') return parts.length === 1 ? vimeo(parts[0]) : null
  if (host === 'player.vimeo.com') return parts[0] === 'video' ? vimeo(parts[1]) : null
  return null
}

/** Embed address for a stored canonical link, or null if it is not one we recognise. */
export function embedUrl(stored: string): string | null {
  return parseVideoUrl(stored)?.embed ?? null
}
