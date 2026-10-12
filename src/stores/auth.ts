import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { Session, User } from '@supabase/supabase-js'
import { supabase, isSupabaseConfigured } from '@/lib/supabase'
import type { Profile, SignupIntent } from '@/types/domain'

export const useAuthStore = defineStore('auth', () => {
  const session = ref<Session | null>(null)
  const profile = ref<Profile | null>(null)
  const isPlatformAdmin = ref(false)
  const ready = ref(false)

  const user = computed<User | null>(() => session.value?.user ?? null)
  const isAuthenticated = computed(() => !!session.value)
  const displayName = computed(() => profile.value?.full_name || user.value?.email || 'Account')

  async function loadProfile() {
    if (!user.value) { profile.value = null; isPlatformAdmin.value = false; return }
    const [p, a] = await Promise.all([
      supabase.from('profiles').select('id, full_name, avatar_url, country, signup_intent')
        .eq('id', user.value.id).maybeSingle(),
      supabase.rpc('is_platform_admin'),
    ])
    profile.value = p.data as Profile | null
    isPlatformAdmin.value = a.data === true
  }

  async function init() {
    if (ready.value) return
    if (!isSupabaseConfigured) { ready.value = true; return }
    const { data } = await supabase.auth.getSession()
    session.value = data.session
    await loadProfile()
    supabase.auth.onAuthStateChange((_event, s) => {
      session.value = s
      // Defer to avoid calling Supabase inside the auth callback.
      setTimeout(loadProfile, 0)
    })
    ready.value = true
  }

  async function signIn(email: string, password: string) {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) throw error
    await loadProfile()
  }

  /**
   * One account system, two journeys. `intent` records which journey the person chose:
   *  - 'learner'   joins the official Tech Village LMS as a student (done by a database trigger)
   *  - 'workspace' gets no membership until they finish creating their own workspace
   */
  async function signUp(fullName: string, email: string, password: string, intent: SignupIntent, plan?: string, next?: string) {
    // Only same-site invitation links are allowed as a post-verification landing page.
    const landing = next && /^\/invite\/[A-Za-z0-9]{20,100}$/.test(next) ? next : '/hub'
    const { data, error } = await supabase.auth.signUp({
      email, password,
      options: {
        data: { full_name: fullName, signup_intent: intent, ...(plan ? { intended_plan: plan } : {}) },
        emailRedirectTo: `${location.origin}${landing}`,
      },
    })
    if (error) throw error
    if (data.session) { session.value = data.session; await loadProfile() }
    // With email verification on, there is no session until the link is clicked.
    return { needsVerification: !data.session }
  }

  async function resetPassword(email: string) {
    const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo: `${location.origin}/reset-password` })
    if (error) throw error
  }

  async function updatePassword(password: string) {
    const { error } = await supabase.auth.updateUser({ password })
    if (error) throw error
  }

  async function signOut() {
    await supabase.auth.signOut()
    session.value = null
    profile.value = null
    isPlatformAdmin.value = false
  }

  return {
    session, profile, user, ready, isAuthenticated, isPlatformAdmin, displayName,
    init, loadProfile, signIn, signUp, resetPassword, updatePassword, signOut,
  }
})
