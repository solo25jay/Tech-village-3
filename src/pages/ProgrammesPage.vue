<script setup lang="ts">
import BaseButton from '@/components/BaseButton.vue'
import { PROGRAMMES } from '@/content/programmes'
</script>

<template>
  <section class="mx-auto max-w-6xl px-4 py-14 sm:px-6 sm:py-20">
    <h1 class="max-w-3xl text-4xl font-extrabold sm:text-5xl">Learning paths</h1>
    <p class="mt-5 max-w-prose text-lg text-muted">
      Each path moves from fundamentals to projects you can show to employers and clients.
    </p>
    <p class="mt-4 max-w-prose rounded-control bg-brand-soft px-4 py-3 text-sm text-brand-strong" role="note">
      Enrolment is not open yet. Tell us which path interests you and we will contact you when cohorts are announced.
    </p>

    <ul class="mt-10 grid gap-5 md:grid-cols-2 lg:grid-cols-3">
      <li v-for="p in PROGRAMMES" :key="p.slug" class="panel flex flex-col p-6">
        <h2 class="text-xl font-bold">{{ p.title }}</h2>
        <p class="mt-2 text-muted">{{ p.summary }}</p>
        <ul class="mt-4 flex flex-wrap gap-2" aria-label="Skills covered">
          <li v-for="s in p.skills" :key="s" class="rounded-full bg-sunken px-3 py-1 text-xs font-medium">{{ s }}</li>
        </ul>
        <div class="mt-6 pt-2">
          <BaseButton :to="{ name: 'contact', query: { topic: 'programme', about: p.title } }" variant="secondary">Register interest</BaseButton>
        </div>
      </li>
    </ul>
  </section>
</template>
