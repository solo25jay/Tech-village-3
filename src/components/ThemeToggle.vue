<script setup lang="ts">
import { useTheme } from '@/composables/useTheme'
const { isDark, toggle } = useTheme()
</script>

<template>
  <button type="button" class="grid h-10 w-10 place-items-center rounded-control text-muted hover:bg-sunken hover:text-ink"
          :aria-label="isDark ? 'Switch to light theme' : 'Switch to dark theme'" @click="toggle">
    <svg v-if="isDark" class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
      <circle cx="12" cy="12" r="4" /><path stroke-linecap="round" d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
    </svg>
    <svg v-else class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
      <path stroke-linecap="round" stroke-linejoin="round" d="M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5Z" />
    </svg>
  </button>
</template>
