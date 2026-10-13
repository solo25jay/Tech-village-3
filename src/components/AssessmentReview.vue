<script setup lang="ts">
import { ref, reactive, watch } from 'vue'
import BaseField from '@/components/BaseField.vue'
import BaseTextarea from '@/components/BaseTextarea.vue'
import BaseButton from '@/components/BaseButton.vue'
import { getAssessment, attemptsForReview, submissionsForReview, gradeSubmission, type Assessment } from '@/lib/assessments'
import { assessmentEditPath, courseEditPath, type Scope } from '@/lib/paths'
import { friendlyError } from '@/lib/errors'

const props = defineProps<{ orgId: string; assessmentId: string; scope: Scope }>()

type AttemptRow = Awaited<ReturnType<typeof attemptsForReview>>[number]
type SubRow = Awaited<ReturnType<typeof submissionsForReview>>[number]
const a = ref<Assessment | null>(null)
const attempts = ref<AttemptRow[]>([])
const subs = ref<SubRow[]>([])
const points = reactive<Record<string, string>>({})
const feedback = reactive<Record<string, string>>({})
const loading = ref(true); const busyId = ref<string | null>(null)
const error = ref(''); const notice = ref('')

async function load() {
  loading.value = true; error.value = ''
  try {
    a.value = await getAssessment(props.assessmentId)
    if (!a.value) return
    if (a.value.kind === 'quiz') attempts.value = await attemptsForReview(props.assessmentId)
    else {
      subs.value = await submissionsForReview(props.assessmentId)
      for (const s of subs.value) { points[s.id] = s.points === null ? '' : String(s.points); feedback[s.id] = s.feedback ?? '' }
    }
  } catch (e) { error.value = friendlyError(e) } finally { loading.value = false }
}
watch(() => props.assessmentId, load, { immediate: true })

async function grade(s: SubRow) {
  error.value = ''; notice.value = ''
  const p = Number.parseInt(points[s.id] ?? '', 10)
  if (!Number.isFinite(p)) { error.value = 'Enter the points to award.'; return }
  busyId.value = s.id
  try { await gradeSubmission(s.id, p, feedback[s.id] ?? ''); notice.value = `Graded ${s.name}.`; await load() }
  catch (e) { error.value = friendlyError(e) } finally { busyId.value = null }
}
const fmt = (d: string) => new Date(d).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })
const isLate = (s: SubRow) => !!(a.value?.due_at && new Date(s.submitted_at) > new Date(a.value.due_at))
</script>

<template>
  <div class="max-w-4xl">
    <p v-if="loading" class="text-muted" role="status">Loading…</p>
    <div v-else-if="!a">
      <h1 class="text-2xl font-bold">Not found</h1>
      <p class="mt-2 text-muted">You may not be allowed to review this assessment.</p>
    </div>
    <template v-else>
      <RouterLink :to="courseEditPath(scope, a.course_id)" class="link text-sm">Back to course editor</RouterLink>
      <div class="mt-2 flex flex-wrap items-center justify-between gap-3">
        <h1 class="text-3xl font-bold">{{ a.title }}: {{ a.kind === 'quiz' ? 'results' : 'submissions' }}</h1>
        <BaseButton variant="secondary" :to="assessmentEditPath(scope, a.course_id, a.id)">Edit</BaseButton>
      </div>
      <p v-if="error" role="alert" class="mt-4 rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
      <p v-if="notice" role="status" class="mt-4 rounded-control bg-brand-soft px-3 py-2 text-sm text-brand-strong">{{ notice }}</p>

      <template v-if="a.kind === 'quiz'">
        <p v-if="!attempts.length" class="panel mt-6 p-6 text-sm text-muted">No one has taken this quiz yet.</p>
        <div v-else class="panel mt-6 overflow-x-auto">
          <table class="w-full min-w-[30rem] text-left text-sm">
            <thead class="border-b border-line text-muted"><tr>
              <th scope="col" class="px-4 py-3 font-medium">Learner</th><th scope="col" class="px-4 py-3 font-medium">Attempt</th>
              <th scope="col" class="px-4 py-3 font-medium">Score</th><th scope="col" class="px-4 py-3 font-medium">Result</th><th scope="col" class="px-4 py-3 font-medium">When</th>
            </tr></thead>
            <tbody class="divide-y divide-line">
              <tr v-for="t in attempts" :key="t.id">
                <td class="px-4 py-3 font-medium">{{ t.name }}</td><td class="px-4 py-3">{{ t.attempt_no }}</td>
                <td class="px-4 py-3">{{ t.score_percent }}%</td>
                <td class="px-4 py-3"><span :class="t.passed ? 'text-mint-text' : 'text-muted'">{{ t.passed ? 'Passed' : 'Not passed' }}</span></td>
                <td class="px-4 py-3 text-muted">{{ fmt(t.submitted_at) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </template>

      <template v-else>
        <p v-if="!subs.length" class="panel mt-6 p-6 text-sm text-muted">No submissions yet.</p>
        <ul v-else class="mt-6 space-y-4">
          <li v-for="s in subs" :key="s.id" class="panel p-5">
            <div class="flex flex-wrap items-baseline justify-between gap-2">
              <h2 class="font-display text-lg font-semibold">{{ s.name }}</h2>
              <p class="text-sm text-muted">Submitted {{ fmt(s.submitted_at) }}<span v-if="isLate(s)" class="text-warn"> (late)</span> · <span class="capitalize">{{ s.status }}</span></p>
            </div>
            <p class="mt-3 max-h-64 overflow-auto whitespace-pre-line rounded-control bg-sunken p-4 text-sm">{{ s.body }}</p>
            <form class="mt-4 grid gap-4 sm:grid-cols-[8rem_1fr_auto] sm:items-end" @submit.prevent="grade(s)">
              <BaseField v-model="points[s.id]" :label="`Points (max ${a.max_points})`" type="number" />
              <BaseTextarea v-model="feedback[s.id]" label="Feedback" :rows="2" :maxlength="5000" />
              <BaseButton type="submit" :loading="busyId === s.id">{{ s.status === 'graded' ? 'Update grade' : 'Save grade' }}</BaseButton>
            </form>
          </li>
        </ul>
      </template>
    </template>
  </div>
</template>
