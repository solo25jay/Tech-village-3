<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import BaseField from '@/components/BaseField.vue'
import BaseButton from '@/components/BaseButton.vue'
import { useAuthStore } from '@/stores/auth'
import { friendlyError } from '@/lib/errors'

const auth = useAuthStore()
const router = useRouter()
const password = ref('')
const confirm = ref('')
const error = ref('')
const busy = ref(false)

async function submit() {
  error.value = ''
  if (password.value.length < 8) { error.value = 'Use a password with at least 8 characters.'; return }
  if (password.value !== confirm.value) { error.value = 'The two passwords do not match.'; return }
  busy.value = true
  try {
    await auth.updatePassword(password.value)
    router.replace({ name: 'hub' })
  } catch (e) { error.value = friendlyError(e) } finally { busy.value = false }
}
</script>

<template>
  <div class="mx-auto max-w-md px-4 py-14 sm:py-20">
    <template v-if="auth.isAuthenticated">
      <h1 class="text-3xl font-bold">Choose a new password</h1>
      <form class="panel mt-6 space-y-5 p-6" @submit.prevent="submit">
        <BaseField v-model="password" label="New password" type="password" autocomplete="new-password" hint="At least 8 characters." required :minlength="8" />
        <BaseField v-model="confirm" label="Confirm new password" type="password" autocomplete="new-password" required />
        <p v-if="error" role="alert" class="rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
        <BaseButton type="submit" class="w-full" :loading="busy">Save password</BaseButton>
      </form>
    </template>
    <template v-else>
      <h1 class="text-3xl font-bold">This link has expired</h1>
      <p class="mt-3 text-muted">Reset links work once and expire. Request a new one from the sign-in page.</p>
      <RouterLink to="/login" class="link mt-6 inline-block">Go to sign in</RouterLink>
    </template>
  </div>
</template>
