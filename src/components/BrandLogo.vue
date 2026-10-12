<script setup lang="ts">
withDefaults(defineProps<{ size?: 'sm' | 'md' | 'lg'; showWordmark?: boolean }>(), { size: 'md', showWordmark: true })
const heights = { sm: 'h-8', md: 'h-10', lg: 'h-16' } as const
const text = { sm: 'text-base', md: 'text-lg', lg: 'text-3xl' } as const
</script>

<template>
  <span class="inline-flex items-center gap-2.5">
    <!-- Swap for the SVG mark when the designer supplies one -->
    <img src="/brand/mark-on-white.png" alt="" :class="[heights[size], 'w-auto rounded-md dark:hidden']" />
    <img src="/brand/mark-on-black.png" alt="" :class="[heights[size], 'hidden w-auto rounded-md dark:block']" />
    <span v-if="showWordmark" :class="['font-display font-extrabold leading-none tracking-tight', text[size]]">
      <span class="text-navy">Tech</span> <span class="text-brand">Village</span>
    </span>
    <span v-else class="sr-only">Tech Village</span>
  </span>
</template>
