<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import BaseField from '@/components/BaseField.vue'
import BaseButton from '@/components/BaseButton.vue'
import SetupNotice from '@/components/SetupNotice.vue'
import { useAuthStore } from '@/stores/auth'
import { isSupabaseConfigured } from '@/lib/supabase'
import { friendlyError } from '@/lib/errors'

const auth = useAuthStore()
const router = useRouter()
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
    const { needsVerification } = await auth.signUp(fullName.value.trim(), email.value.trim(), password.value, 'learner')
    if (needsVerification) verifySent.value = true
    else router.replace({ name: 'hub' })
  } catch (e) { error.value = friendlyError(e) } finally { busy.value = false }
}
</script>

<template>
  <div class="mx-auto max-w-md px-4 py-14 sm:py-20">
    <template v-if="verifySent">
      <h1 class="text-3xl font-bold">Check your email</h1>
      <p class="mt-3 text-muted">We sent a confirmation link to <strong class="text-ink">{{ email }}</strong>. Open it and you will land in your Tech Village learner dashboard.</p>
      <RouterLink to="/login" class="link mt-6 inline-block">Go to sign in</RouterLink>
    </template>
    <template v-else>
      <p class="text-sm font-semibold text-brand">Join Tech Village</p>
      <h1 class="mt-1 text-3xl font-bold">Create your learner account</h1>
      <p class="mt-2 text-muted">Just your details. You will go straight to the official Tech Village learning platform.</p>
      <div class="mt-6"><SetupNotice /></div>
      <form class="panel mt-6 space-y-5 p-6" @submit.prevent="submit">
        <BaseField v-model="fullName" label="Full name" autocomplete="name" required />
        <BaseField v-model="email" label="Email" type="email" autocomplete="email" required />
        <BaseField v-model="password" label="Password" type="password" autocomplete="new-password" hint="At least 8 characters." required :minlength="8" />
        <p v-if="error" role="alert" class="rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
        <BaseButton type="submit" class="w-full" :loading="busy" :disabled="!isSupabaseConfigured">Join Tech Village</BaseButton>
      </form>
      <p class="mt-6 text-sm text-muted">
        Already registered? <RouterLink to="/login" class="link">Sign in</RouterLink><br />
        Setting up a school or academy instead? <RouterLink to="/signup/lms" class="link">Create your own LMS</RouterLink>
      </p>
    </template>
  </div>
</template>
