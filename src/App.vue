<script setup lang="ts">
import { watch } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'

const auth = useAuthStore()
const ws = useWorkspaceStore()
const router = useRouter()

// When the session ends, clear tenant state and leave the workspace area.
watch(() => auth.isAuthenticated, (signedIn, wasSignedIn) => {
  if (wasSignedIn && !signedIn) {
    ws.reset()
    if (router.currentRoute.value.meta.requiresAuth) router.replace({ name: 'login' })
  }
})
</script>

<template>
  <RouterView />
</template>
