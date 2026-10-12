<script setup lang="ts">
import BaseButton from '@/components/BaseButton.vue'
const pillars = [
  { title: 'Learn', body: 'Structured learning paths with practical exercises, assessments and mentors who answer questions.' },
  { title: 'Build', body: 'Real projects and browser-based coding labs, so skills turn into a portfolio rather than a list of videos watched.' },
  { title: 'Earn', body: 'Professional profiles, certificates that others can verify, and a route to jobs, freelance work and clients.' },
]
</script>

<template>
  <section class="mx-auto max-w-6xl px-4 py-14 sm:px-6 sm:py-20">
    <h1 class="max-w-3xl text-4xl font-extrabold sm:text-5xl">A village for people who build with technology</h1>
    <p class="mt-6 max-w-prose text-lg text-muted">
      Tech Village exists so that learning technology leads somewhere. We combine teaching, practice, mentorship and community,
      and we make the same tools available to tutors, academies, schools and companies who want to teach in their own way.
    </p>
  </section>

  <section class="border-y border-line bg-raised">
    <div class="mx-auto grid max-w-6xl gap-10 px-4 py-14 sm:px-6 md:grid-cols-3">
      <div v-for="p in pillars" :key="p.title">
        <h2 class="text-2xl font-bold text-brand">{{ p.title }}</h2>
        <p class="mt-3 text-muted">{{ p.body }}</p>
      </div>
    </div>
  </section>

  <section class="mx-auto grid max-w-6xl gap-10 px-4 py-14 sm:px-6 md:grid-cols-2">
    <div>
      <h2 class="text-2xl font-bold">Two ways to use Tech Village</h2>
      <p class="mt-3 max-w-prose text-muted">
        Learn from our own programmes, or open a workspace and run your own. Each workspace has its own students, courses,
        instructors and settings, kept private from every other workspace.
      </p>
    </div>
    <div class="flex flex-wrap content-start gap-3 md:justify-end">
      <BaseButton to="/programmes" variant="secondary" size="lg">Explore programmes</BaseButton>
      <BaseButton to="/pricing" size="lg">See workspace plans</BaseButton>
    </div>
  </section>
</template>
