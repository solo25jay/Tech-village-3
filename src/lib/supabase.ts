import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

/** False until the project owner adds Supabase credentials. The UI shows a setup state instead of failing silently. */
export const isSupabaseConfigured = Boolean(url && anonKey)

// The anon key is public by design. Data is protected by Row Level Security, not by hiding this key.
export const supabase = createClient(url ?? 'http://localhost:54321', anonKey ?? 'missing-anon-key', {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
})
