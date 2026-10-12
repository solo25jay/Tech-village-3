<script setup lang="ts">
import { useRouter } from 'vue-router'
import BrandLogo from '@/components/BrandLogo.vue'
import ThemeToggle from '@/components/ThemeToggle.vue'
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'

const auth = useAuthStore()
const ws = useWorkspaceStore()
const router = useRouter()

async function signOut() {
  await auth.signOut()
  router.replace({ name: 'home' })
}
</script>

<template>
  <div class="min-h-screen">
    <a href="#content" class="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-50 focus:rounded-control focus:bg-raised focus:px-4 focus:py-2">Skip to content</a>
    <header class="border-b border-line bg-raised">
      <div class="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-4 sm:px-6">
        <RouterLink :to="{ name: 'learn-dashboard' }" aria-label="Tech Village learning home"><BrandLogo size="md" /></RouterLink>
        <nav class="flex items-center gap-1" aria-label="Account">
          <RouterLink :to="{ name: 'learn-courses' }" class="rounded-control px-3 py-2 text-sm font-medium text-muted hover:bg-sunken hover:text-ink">Courses</RouterLink>
          <RouterLink v-if="ws.workspaces.length" :to="{ name: 'dashboard' }" class="hidden rounded-control px-3 py-2 text-sm font-medium text-muted hover:bg-sunken hover:text-ink sm:block">
            My workspace
          </RouterLink>
          <RouterLink v-if="auth.isPlatformAdmin" :to="{ name: 'admin' }" class="hidden rounded-control px-3 py-2 text-sm font-medium text-muted hover:bg-sunken hover:text-ink sm:block">
            Platform admin
          </RouterLink>
          <ThemeToggle />
          <span class="hidden max-w-[10rem] truncate px-2 text-sm font-medium sm:block">{{ auth.displayName }}</span>
          <button type="button" class="rounded-control px-3 py-2 text-sm font-medium text-muted hover:bg-sunken hover:text-ink" @click="signOut">Sign out</button>
        </nav>
      </div>
    </header>
    <main id="content" class="mx-auto max-w-6xl px-4 py-8 sm:px-6"><RouterView /></main>
  </div>
</template>
