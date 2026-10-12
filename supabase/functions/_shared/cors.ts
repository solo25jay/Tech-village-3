/** Browsers may call these functions only from the configured site origin(s). */
export function corsHeaders(req: Request, allowed: string): Record<string, string> {
  const origins = allowed.split(',').map(s => s.trim()).filter(Boolean)
  const origin = req.headers.get('origin') ?? ''
  const ok = origins.includes(origin)
  return {
    'Access-Control-Allow-Origin': ok ? origin : (origins[0] ?? ''),
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    Vary: 'Origin',
  }
}

export function json(body: unknown, status: number, cors: Record<string, string>): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })
}
