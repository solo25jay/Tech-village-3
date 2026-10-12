<script setup lang="ts">
import { ref, computed } from 'vue'
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
const token = computed(() => { const t = route.query.invite; return typeof t === 'string' && /^[A-Za-z0-9]{20,100}$/.test(t) ? t : '' })
const fullName = ref('')
const email = ref('')
const password = ref('')
const error = ref('')
const busy = ref(false)
const verifySent = ref(false)

async function submit() {
  error.value = ''
  if (password.value.length < 8) { error.value = 'Use a password with at least 8 characters.'; return }
  busy.value = true
  try {
    const { needsVerification } = await auth.signUp(fullName.value.trim(), email.value.trim(), password.value, 'invited', undefined, `/invite/${token.value}`)
    if (needsVerification) verifySent.value = true
    else router.replace(`/invite/${token.value}`)
  } catch (e) { error.value = friendlyError(e) } finally { busy.value = false }
}
</script>

<template>
  <div class="mx-auto max-w-md px-4 py-14 sm:py-20">
    <template v-if="!token">
      <h1 class="text-3xl font-bold">Invitation link needed</h1>
      <p class="mt-3 text-muted">Open the invitation link you were sent, then choose “Create an account”.</p>
    </template>
    <template v-else-if="verifySent">
      <h1 class="text-3xl font-bold">Check your email</h1>
      <p class="mt-3 text-muted">We sent a confirmation link to <strong class="text-ink">{{ email }}</strong>. After you confirm, you will return to your invitation to accept it.</p>
    </template>
    <template v-else>
      <h1 class="text-3xl font-bold">Create your account</h1>
      <p class="mt-2 text-muted">Use the email address the invitation was sent to. You will not be added to anything else.</p>
      <div class="mt-6"><SetupNotice /></div>
      <form class="panel mt-6 space-y-5 p-6" @submit.prevent="submit">
        <BaseField v-model="fullName" label="Full name" autocomplete="name" required />
        <BaseField v-model="email" label="Email" type="email" autocomplete="email" required />
        <BaseField v-model="password" label="Password" type="password" autocomplete="new-password" hint="At least 8 characters." required :minlength="8" />
        <p v-if="error" role="alert" class="rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
        <BaseButton type="submit" class="w-full" :loading="busy" :disabled="!isSupabaseConfigured">Create account</BaseButton>
      </form>
      <p class="mt-6 text-sm text-muted">Already registered? <RouterLink :to="{ name: 'login', query: { next: `/invite/${token}` } }" class="link">Sign in</RouterLink></p>
    </template>
  </div>
</template>
