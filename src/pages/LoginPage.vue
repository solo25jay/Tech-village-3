<script setup lang="ts">
import { ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import BaseField from '@/components/BaseField.vue'
import BaseButton from '@/components/BaseButton.vue'
import SetupNotice from '@/components/SetupNotice.vue'
import { useAuthStore } from '@/stores/auth'
import { isSupabaseConfigured } from '@/lib/supabase'
import { friendlyError } from '@/lib/errors'

const auth = useAuthStore()
const route = useRoute()
const router = useRouter()
const email = ref('')
const password = ref('')
const error = ref('')
const info = ref('')
const busy = ref(false)

// Only follow same-site relative paths after sign-in.
function safeNext(): string {
  const n = route.query.next
  return typeof n === 'string' && n.startsWith('/') && !n.startsWith('//') ? n : '/hub'
}

async function submit() {
  error.value = ''; info.value = ''; busy.value = true
  try {
    await auth.signIn(email.value.trim(), password.value)
    router.replace(safeNext())
  } catch (e) { error.value = friendlyError(e) } finally { busy.value = false }
}

async function forgot() {
  error.value = ''; info.value = ''
  if (!email.value.trim()) { error.value = 'Enter your email above, then select "Forgot password".'; return }
  try {
    await auth.resetPassword(email.value.trim())
    info.value = 'If that email has an account, a reset link is on its way.'
  } catch (e) { error.value = friendlyError(e) }
}
</script>

<template>
  <div class="mx-auto max-w-md px-4 py-14 sm:py-20">
    <h1 class="text-3xl font-bold">Sign in</h1>
    <p class="mt-2 text-muted">Welcome back to Tech Village.</p>
    <div class="mt-6"><SetupNotice /></div>
    <form class="panel mt-6 space-y-5 p-6" @submit.prevent="submit">
      <BaseField v-model="email" label="Email" type="email" autocomplete="email" required />
      <BaseField v-model="password" label="Password" type="password" autocomplete="current-password" required />
      <p v-if="error" role="alert" class="rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
      <p v-if="info" role="status" class="rounded-control bg-brand-soft px-3 py-2 text-sm text-brand-strong">{{ info }}</p>
      <BaseButton type="submit" class="w-full" :loading="busy" :disabled="!isSupabaseConfigured">Sign in</BaseButton>
      <button type="button" class="link text-sm" @click="forgot">Forgot password</button>
    </form>
    <p class="mt-6 text-sm text-muted">New here? <RouterLink to="/signup" class="link">Sign up</RouterLink></p>
  </div>
</template>
