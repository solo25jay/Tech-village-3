<script setup lang="ts">
import BaseButton from '@/components/BaseButton.vue'
</script>

<template>
  <div class="mx-auto max-w-5xl px-4 py-14 sm:px-6 sm:py-20">
    <h1 class="text-3xl font-bold sm:text-4xl">How do you want to use Tech Village?</h1>
    <p class="mt-3 max-w-prose text-muted">These are two different things. Pick the one that fits, because they lead to different accounts.</p>

    <div class="mt-10 grid gap-6 md:grid-cols-2">
      <section class="panel flex flex-col p-7" aria-labelledby="learn-title">
        <p class="text-sm font-semibold text-brand">For learners</p>
        <h2 id="learn-title" class="mt-1 text-2xl font-bold">Join Tech Village</h2>
        <p class="mt-3 text-muted">
          You want to learn, build projects, get mentored and take part in the official Tech Village community. No organisation or setup needed.
        </p>
        <ul class="mt-5 space-y-2 text-sm">
          <li>Official courses and learning paths</li>
          <li>Coding labs, assignments and certificates</li>
          <li>Mentorship, events and the Tech Village community</li>
        </ul>
        <div class="mt-auto pt-8"><BaseButton to="/signup/learner" size="lg" class="w-full">Join Tech Village</BaseButton></div>
      </section>

      <section class="panel flex flex-col border-brand/40 p-7" aria-labelledby="lms-title">
        <p class="text-sm font-semibold text-violet">For schools, academies and tutors</p>
        <h2 id="lms-title" class="mt-1 text-2xl font-bold">Create Your Own LMS</h2>
        <p class="mt-3 text-muted">
          You want your own learning platform for your own students. You will register your organisation and become the owner of an independent workspace.
        </p>
        <ul class="mt-5 space-y-2 text-sm">
          <li>Your own courses, students, instructors and branding</li>
          <li>Separate from the official Tech Village LMS</li>
          <li>Choose a plan, with a free trial on paid plans</li>
        </ul>
        <div class="mt-auto pt-8"><BaseButton to="/signup/lms" size="lg" variant="secondary" class="w-full">Create Your LMS</BaseButton></div>
      </section>
    </div>

    <p class="mt-8 text-sm text-muted">Already have an account? <RouterLink to="/login" class="link">Sign in</RouterLink></p>
  </div>
</template>
