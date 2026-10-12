<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import BaseButton from '@/components/BaseButton.vue'
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'

/**
 * Signed-in traffic cop. One person can be a Tech Village learner, a workspace owner, or both,
 * so we decide where to send them instead of guessing at sign-in.
 */
const auth = useAuthStore()
const ws = useWorkspaceStore()
const router = useRouter()
const deciding = ref(true)
const failed = ref(false)

async function decide() {
  deciding.value = true; failed.value = false
  try {
    await auth.loadProfile()
    await ws.load()
  } catch { failed.value = true; deciding.value = false; return }

  const learner = !!ws.official
  const customer = ws.workspaces.length > 0
  // Chose "Create your own LMS" but never finished, and has nothing else to open: resume setup.
  const wantsWorkspace = auth.profile?.signup_intent === 'workspace' && !ws.ownedWorkspace && !learner

  if (wantsWorkspace) return router.replace({ name: 'signup-lms' })   // finish the workspace setup they started
  if (customer && !learner) return router.replace({ name: 'dashboard' })
  if (learner && !customer) return router.replace({ name: 'learn-dashboard' })
  if (!learner && !customer) return router.replace({ name: 'signup' })
  deciding.value = false                                               // both: let them choose
}
onMounted(decide)
</script>

<template>
  <div class="mx-auto max-w-3xl px-4 py-14 sm:py-20">
    <p v-if="deciding && !failed" class="text-muted" role="status">Loading your account…</p>

    <div v-else-if="failed" role="alert">
      <h1 class="text-2xl font-bold">We could not load your account</h1>
      <p class="mt-2 text-muted">Check your connection and try again.</p>
      <BaseButton class="mt-4" @click="decide">Try again</BaseButton>
    </div>

    <template v-else>
      <h1 class="text-3xl font-bold">Where would you like to go?</h1>
      <p class="mt-2 text-muted">You have more than one space on Tech Village.</p>
      <div class="mt-8 grid gap-4 sm:grid-cols-2">
        <RouterLink :to="{ name: 'learn-dashboard' }" class="panel block p-6 hover:border-brand">
          <p class="text-sm font-semibold text-brand">Learning</p>
          <p class="mt-1 font-display text-xl font-bold">Tech Village</p>
          <p class="mt-2 text-sm text-muted">Your official learner dashboard.</p>
        </RouterLink>
        <RouterLink v-for="w in ws.workspaces" :key="w.org_id" :to="{ name: 'dashboard' }" class="panel block p-6 hover:border-brand" @click="ws.switchTo(w.org_id)">
          <p class="text-sm font-semibold text-violet">Workspace · {{ w.role_name }}</p>
          <p class="mt-1 font-display text-xl font-bold">{{ w.workspace_name }}</p>
          <p class="mt-2 text-sm text-muted">{{ w.status === 'suspended' ? 'Suspended' : 'Manage your LMS.' }}</p>
        </RouterLink>
      </div>
    </template>
  </div>
</template>
