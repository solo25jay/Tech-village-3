<script setup lang="ts">
import BaseButton from '@/components/BaseButton.vue'
import { ORG_TYPE_LABELS } from '@/types/domain'
const audiences = ['school', 'university_college', 'training_academy', 'coding_bootcamp', 'private_tutoring', 'corporate_training'] as const
</script>

<template>
  <section class="mx-auto grid max-w-6xl items-center gap-10 px-4 py-14 sm:px-6 lg:grid-cols-[1.15fr_1fr] lg:py-24">
    <div>
      <h1 class="text-4xl font-extrabold leading-[1.08] sm:text-6xl">
        Learn the skill.<br />Build the proof.<br />Earn from it.
      </h1>
      <p class="mt-6 max-w-prose text-lg text-muted">
        Join Tech Village to learn technology skills, get mentored and build a career. Or use our platform to run your own
        independent, branded learning space for your students.
      </p>
      <div class="mt-8 flex flex-wrap gap-3">
        <BaseButton to="/signup/learner" size="lg">Join Tech Village</BaseButton>
        <BaseButton to="/signup/lms" size="lg" variant="secondary">Create your LMS</BaseButton>
      </div>
    </div>
    <div class="flex justify-center lg:justify-end">
      <img src="/brand/mark-on-white.png" alt="Tech Village logo: a house made of connected circuit nodes with a growth arrow"
           class="w-full max-w-md rounded-panel dark:hidden" />
      <img src="/brand/mark-on-black.png" alt="Tech Village logo: a house made of connected circuit nodes with a growth arrow"
           class="hidden w-full max-w-md rounded-panel dark:block" />
    </div>
  </section>

  <section class="border-y border-line bg-raised">
    <div class="mx-auto grid max-w-6xl gap-10 px-4 py-14 sm:px-6 md:grid-cols-2">
      <div>
        <h2 class="text-2xl font-bold">Learn with Tech Village</h2>
        <p class="mt-3 max-w-prose text-muted">
          Official courses and learning paths, coding labs, mentorship, community and opportunities. Everything is run by Tech Village.
        </p>
      </div>
      <div>
        <h2 class="text-2xl font-bold">Run your own LMS</h2>
        <p class="mt-3 max-w-prose text-muted">
          Each workspace is completely independent, with its own students, courses, staff, branding and billing. Nothing is shared with other workspaces.
        </p>
        <ul class="mt-4 flex flex-wrap gap-2 text-sm">
          <li v-for="t in audiences" :key="t" class="rounded-full border border-line px-3 py-1 text-muted">{{ ORG_TYPE_LABELS[t] }}</li>
        </ul>
      </div>
    </div>
  </section>
</template>
