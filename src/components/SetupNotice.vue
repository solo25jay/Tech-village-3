<script setup lang="ts">
import { isSupabaseConfigured } from '@/lib/supabase'
</script>

<template>
  <div v-if="!isSupabaseConfigured" role="status" class="rounded-control border border-warn/40 bg-warn-soft p-4 text-sm text-warn">
    <p class="font-semibold">Supabase is not connected yet</p>
    <p class="mt-1">
      Copy <code class="font-mono">.env.example</code> to <code class="font-mono">.env</code>, add your project URL and anon key,
      then restart the dev server. Sign in and sign up stay disabled until then.
    </p>
  </div>
</template>
