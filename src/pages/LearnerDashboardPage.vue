<script setup lang="ts">
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'
const auth = useAuthStore()
const ws = useWorkspaceStore()
</script>

<template>
  <div class="max-w-4xl">
    <h1 class="text-3xl font-bold">Welcome, {{ auth.displayName.split(' ')[0] }}</h1>
    <p class="mt-2 text-muted">You are a learner on the official Tech Village platform.</p>

    <section class="panel mt-8 p-6">
      <h2 class="text-lg font-semibold">Your learning space is ready</h2>
      <p class="mt-2 max-w-prose text-sm text-muted">
        Your account is active. Browse and enrol in courses, work through lessons and track your progress. Learning paths, coding labs,
        goals and roadmaps, mentorship, events, certificates and opportunities arrive in later phases and will appear here as they ship.
      </p>
      <RouterLink :to="{ name: 'learn-courses' }" class="link mt-4 inline-block text-sm">Browse courses</RouterLink>
    </section>

    <section v-if="!ws.workspaces.length" class="panel mt-4 p-6">
      <h2 class="text-lg font-semibold">Teach or train people yourself?</h2>
      <p class="mt-2 max-w-prose text-sm text-muted">
        You can also create your own independent LMS for your students. It is separate from your learner account here.
      </p>
      <RouterLink to="/signup/lms" class="link mt-3 inline-block text-sm">Create your own LMS</RouterLink>
    </section>
  </div>
</template>
