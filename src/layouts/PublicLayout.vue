<script setup lang="ts">
import { ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import BrandLogo from '@/components/BrandLogo.vue'
import ThemeToggle from '@/components/ThemeToggle.vue'
import BaseButton from '@/components/BaseButton.vue'
import { useAuthStore } from '@/stores/auth'

const auth = useAuthStore()
const route = useRoute()
const open = ref(false)
watch(() => route.fullPath, () => { open.value = false })

const links = [
  { label: 'Learning paths', to: '/programmes' },
  { label: 'Pricing', to: '/pricing' },
  { label: 'About', to: '/about' },
  { label: 'Contact', to: '/contact' },
]
</script>

<template>
  <div class="flex min-h-screen flex-col">
    <a href="#main" class="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-50 focus:rounded-control focus:bg-raised focus:px-4 focus:py-2">Skip to content</a>
    <header class="sticky top-0 z-40 border-b border-line bg-surface/90 backdrop-blur">
      <div class="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-4 sm:px-6">
        <RouterLink to="/" aria-label="Tech Village home"><BrandLogo size="md" /></RouterLink>

        <nav class="hidden items-center gap-1 md:flex" aria-label="Main">
          <RouterLink v-for="l in links" :key="l.to" :to="l.to"
                      class="rounded-control px-3 py-2 text-sm font-medium text-muted hover:bg-sunken hover:text-ink" active-class="!text-ink">{{ l.label }}</RouterLink>
        </nav>

        <div class="flex items-center gap-1.5">
          <ThemeToggle />
          <template v-if="auth.isAuthenticated">
            <BaseButton to="/hub">Open my account</BaseButton>
          </template>
          <template v-else>
            <BaseButton to="/login" variant="ghost" class="hidden sm:inline-flex">Sign in</BaseButton>
            <BaseButton to="/signup" class="hidden sm:inline-flex">Sign up</BaseButton>
          </template>
          <button type="button" class="grid h-10 w-10 place-items-center rounded-control hover:bg-sunken md:hidden" :aria-expanded="open" aria-controls="mobile-nav" aria-label="Menu" @click="open = !open">
            <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path v-if="!open" stroke-linecap="round" d="M4 7h16M4 12h16M4 17h16" /><path v-else stroke-linecap="round" d="M6 6l12 12M18 6 6 18" /></svg>
          </button>
        </div>
      </div>
      <nav v-if="open" id="mobile-nav" class="border-t border-line bg-raised px-4 py-3 md:hidden" aria-label="Mobile">
        <RouterLink v-for="l in links" :key="l.to" :to="l.to" class="block rounded-control px-3 py-3 font-medium hover:bg-sunken">{{ l.label }}</RouterLink>
        <div v-if="!auth.isAuthenticated" class="mt-2 grid grid-cols-2 gap-2 border-t border-line pt-3">
          <BaseButton to="/login" variant="secondary">Sign in</BaseButton>
          <BaseButton to="/signup">Sign up</BaseButton>
        </div>
      </nav>
    </header>

    <main id="main" class="flex-1"><RouterView /></main>

    <footer class="border-t border-line">
      <div class="mx-auto grid max-w-6xl gap-8 px-4 py-10 text-sm sm:px-6 md:grid-cols-[1.5fr_1fr_1fr]">
        <div>
          <BrandLogo size="sm" />
          <p class="mt-3 max-w-xs text-muted">Learn, build, earn. A learning platform for technology skills, and for anyone who wants to teach them.</p>
        </div>
        <nav aria-label="Explore" class="space-y-2">
          <p class="font-display font-semibold">Explore</p>
          <RouterLink to="/programmes" class="block text-muted hover:text-ink">Learning paths</RouterLink>
          <RouterLink to="/pricing" class="block text-muted hover:text-ink">Pricing</RouterLink>
          <RouterLink to="/about" class="block text-muted hover:text-ink">About</RouterLink>
        </nav>
        <nav aria-label="Account" class="space-y-2">
          <p class="font-display font-semibold">Get started</p>
          <RouterLink to="/signup" class="block text-muted hover:text-ink">Sign up</RouterLink>
          <RouterLink to="/login" class="block text-muted hover:text-ink">Sign in</RouterLink>
          <RouterLink to="/contact" class="block text-muted hover:text-ink">Contact us</RouterLink>
        </nav>
      </div>
      <div class="border-t border-line py-4 text-center text-xs text-muted">&copy; {{ new Date().getFullYear() }} Tech Village</div>
    </footer>
  </div>
</template>
