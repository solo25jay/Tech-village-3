<script setup lang="ts">
import { computed } from 'vue'
import type { RouteLocationRaw } from 'vue-router'
const props = withDefaults(defineProps<{
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger'
  size?: 'md' | 'lg'
  loading?: boolean
  disabled?: boolean
  type?: 'button' | 'submit'
  to?: RouteLocationRaw
}>(), { variant: 'primary', size: 'md', type: 'button' })

const classes = computed(() => [
  'inline-flex items-center justify-center gap-2 rounded-control font-semibold transition-colors',
  'disabled:cursor-not-allowed disabled:opacity-60',
  props.size === 'lg' ? 'h-12 px-6 text-base' : 'h-10 px-4 text-sm',
  {
    primary: 'bg-brand text-brand-on hover:bg-brand-strong',
    secondary: 'border border-line bg-raised text-ink hover:bg-sunken',
    ghost: 'text-ink hover:bg-sunken',
    danger: 'bg-danger text-white hover:opacity-90',
  }[props.variant],
])
</script>

<template>
  <RouterLink v-if="to" :to="to" :class="classes"><slot /></RouterLink>
  <button v-else :type="type" :class="classes" :disabled="disabled || loading" :aria-busy="loading">
    <svg v-if="loading" class="h-4 w-4 animate-spin" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="3" opacity="0.25" />
      <path d="M21 12a9 9 0 0 0-9-9" stroke="currentColor" stroke-width="3" stroke-linecap="round" />
    </svg>
    <slot />
  </button>
</template>
