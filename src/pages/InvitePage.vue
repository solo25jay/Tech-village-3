<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import BaseButton from '@/components/BaseButton.vue'
import { supabase } from '@/lib/supabase'
import { friendlyError } from '@/lib/errors'
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'

interface Preview { workspace_name: string; role_name: string; invited_email: string; status: string; expired: boolean }

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()
const ws = useWorkspaceStore()

const token = computed(() => String(route.params.token ?? ''))
const validShape = computed(() => /^[A-Za-z0-9]{20,100}$/.test(token.value))
const preview = ref<Preview | null>(null)
const loading = ref(true)
const busy = ref(false)
const error = ref('')

const usable = computed(() => !!preview.value && preview.value.status === 'pending' && !preview.value.expired)
const problem = computed(() => {
  if (!validShape.value || !preview.value) return 'This invitation link is not valid.'
  if (preview.value.status !== 'pending') return 'This invitation has already been used or was cancelled.'
  if (preview.value.expired) return 'This invitation has expired. Ask the person who invited you for a new one.'
  return ''
})

onMounted(async () => {
  if (!auth.isAuthenticated || !validShape.value) { loading.value = false; return }
  const { data } = await supabase.rpc('invitation_preview', { p_token: token.value })
  preview.value = ((data as Preview[] | null) ?? [])[0] ?? null
  loading.value = false
})

async function accept() {
  busy.value = true; error.value = ''
  try {
    const { data, error: err } = await supabase.rpc('accept_invitation', { p_token: token.value })
    if (err) throw err
    await ws.load()
    const joined = ws.memberships.find(m => m.org_id === (data as string))
    if (joined?.is_platform_tenant) router.replace({ name: 'learn-dashboard' })
    else { await ws.switchTo(data as string); router.replace({ name: 'dashboard' }) }
  } catch (e) { error.value = friendlyError(e) } finally { busy.value = false }
}
</script>

<template>
  <div class="mx-auto max-w-lg px-4 py-14 sm:py-20">
    <h1 class="text-3xl font-bold">You have been invited</h1>

    <p v-if="!validShape" class="mt-4 text-muted">This invitation link is not valid.</p>

    <template v-else-if="!auth.isAuthenticated">
      <p class="mt-3 text-muted">Sign in or create an account with the email address the invitation was sent to, then come back to this link.</p>
      <div class="mt-6 flex flex-wrap gap-3">
        <BaseButton :to="{ name: 'login', query: { next: `/invite/${token}` } }" size="lg">Sign in</BaseButton>
        <BaseButton :to="{ name: 'signup-invited', query: { invite: token } }" size="lg" variant="secondary">Create an account</BaseButton>
      </div>
    </template>

    <p v-else-if="loading" class="mt-4 text-muted" role="status">Checking your invitation…</p>
    <p v-else-if="problem" role="alert" class="mt-4 rounded-control bg-warn-soft px-4 py-3 text-warn">{{ problem }}</p>

    <template v-else-if="usable && preview">
      <p class="mt-3 text-muted">You can join <strong class="text-ink">{{ preview.workspace_name }}</strong> as <strong class="text-ink">{{ preview.role_name }}</strong>.</p>
      <p class="mt-2 text-sm text-muted">This invitation is for {{ preview.invited_email }}. You must be signed in with that verified email address to accept it.</p>
      <p v-if="error" role="alert" class="mt-4 rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
      <BaseButton class="mt-6" size="lg" :loading="busy" @click="accept">Accept invitation</BaseButton>
    </template>
  </div>
</template>
