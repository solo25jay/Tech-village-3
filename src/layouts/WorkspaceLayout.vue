<script setup lang="ts">
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import BrandLogo from '@/components/BrandLogo.vue'
import ThemeToggle from '@/components/ThemeToggle.vue'
import WorkspaceSwitcher from '@/components/WorkspaceSwitcher.vue'
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'

const auth = useAuthStore()
const ws = useWorkspaceStore()
const router = useRouter()
const menuOpen = ref(false)
const suspended = computed(() => ws.active?.status === 'suspended')

// Navigation is role-aware. Only pages that exist today are listed.
const nav = computed(() => {
  const items = [{ label: 'Dashboard', to: 'dashboard' }, { label: 'Courses', to: 'courses' }]
  if (ws.can('members.manage')) items.push({ label: 'Team', to: 'team' })
  if (ws.can('org.manage')) items.push({ label: 'Organisation settings', to: 'settings' })
  return items
})

async function signOut() {
  await auth.signOut()
  router.replace({ name: 'home' })
}
</script>

<template>
  <div class="min-h-screen lg:grid lg:grid-cols-[17rem_1fr]">
    <a href="#content" class="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-50 focus:rounded-control focus:bg-raised focus:px-4 focus:py-2">Skip to content</a>

    <div class="flex h-14 items-center justify-between border-b border-line bg-raised px-4 lg:hidden">
      <BrandLogo size="sm" />
      <button type="button" class="grid h-10 w-10 place-items-center rounded-control hover:bg-sunken" :aria-expanded="menuOpen" aria-controls="sidebar" aria-label="Toggle menu" @click="menuOpen = !menuOpen">
        <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" d="M4 7h16M4 12h16M4 17h16" /></svg>
      </button>
    </div>

    <aside id="sidebar" class="border-r border-line bg-raised lg:sticky lg:top-0 lg:block lg:h-screen" :class="menuOpen ? 'block' : 'hidden'">
      <div class="flex h-full flex-col gap-6 p-4">
        <RouterLink to="/" class="hidden px-1 lg:block" aria-label="Tech Village home"><BrandLogo size="md" /></RouterLink>
        <WorkspaceSwitcher />
        <nav class="flex-1 space-y-1" aria-label="Workspace">
          <RouterLink v-for="item in nav" :key="item.to" :to="{ name: item.to }" @click="menuOpen = false"
                      class="block rounded-control px-3 py-2 text-sm font-medium text-muted hover:bg-sunken hover:text-ink"
                      active-class="!bg-brand-soft !text-brand">
            {{ item.label }}
          </RouterLink>
        </nav>
        <div class="space-y-3 border-t border-line pt-4">
          <RouterLink v-if="ws.official" :to="{ name: 'learn-dashboard' }" class="block rounded-control px-3 py-2 text-sm font-medium text-muted hover:bg-sunken hover:text-ink">
            My Tech Village learning
          </RouterLink>
          <RouterLink v-else :to="{ name: 'join' }" class="block rounded-control px-3 py-2 text-sm font-medium text-muted hover:bg-sunken hover:text-ink">
            Join Tech Village as a learner
          </RouterLink>
          <RouterLink v-if="auth.isPlatformAdmin" :to="{ name: 'admin' }" class="block rounded-control px-3 py-2 text-sm font-medium text-muted hover:bg-sunken hover:text-ink">
            Platform admin
          </RouterLink>
          <div class="flex items-center justify-between gap-2">
            <div class="min-w-0">
              <p class="truncate text-sm font-semibold">{{ auth.displayName }}</p>
              <button type="button" class="text-xs text-muted underline-offset-4 hover:text-ink hover:underline" @click="signOut">Sign out</button>
            </div>
            <ThemeToggle />
          </div>
        </div>
      </div>
    </aside>

    <main id="content" class="min-w-0 p-4 sm:p-8">
      <div v-if="suspended" role="alert" class="max-w-xl rounded-panel border border-warn/40 bg-warn-soft p-6 text-warn">
        <h1 class="text-xl font-bold !text-warn">This workspace is suspended</h1>
        <p class="mt-2 text-sm">Access is paused by Tech Village. Contact support to find out why and how to restore it.</p>
      </div>
      <RouterView v-else />
    </main>
  </div>
</template>
