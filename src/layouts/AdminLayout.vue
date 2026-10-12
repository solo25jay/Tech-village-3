<script setup lang="ts">
import { useRouter } from 'vue-router'
import BrandLogo from '@/components/BrandLogo.vue'
import ThemeToggle from '@/components/ThemeToggle.vue'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const router = useRouter()
async function signOut() {
  await auth.signOut()
  router.replace({ name: 'home' })
}
</script>

<template>
  <div class="min-h-screen">
    <header class="border-b border-line bg-raised">
      <div class="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-4 sm:px-6">
        <div class="flex items-center gap-3">
          <BrandLogo size="sm" :show-wordmark="false" />
          <span class="font-display text-lg font-bold">Platform admin</span>
        </div>
        <nav class="flex items-center gap-1" aria-label="Admin">
          <RouterLink :to="{ name: 'hub' }" class="rounded-control px-3 py-2 text-sm font-medium text-muted hover:bg-sunken hover:text-ink">Exit admin</RouterLink>
          <ThemeToggle />
          <button type="button" class="rounded-control px-3 py-2 text-sm font-medium text-muted hover:bg-sunken hover:text-ink" @click="signOut">Sign out</button>
        </nav>
      </div>
    </header>
    <main class="mx-auto max-w-6xl px-4 py-8 sm:px-6"><RouterView /></main>
  </div>
</template>
