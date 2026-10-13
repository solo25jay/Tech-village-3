<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import BaseTextarea from '@/components/BaseTextarea.vue'
import BaseButton from '@/components/BaseButton.vue'
import {
  getAssessment, loadQuiz, submitQuiz, myAttempts, mySubmission, saveSubmission,
  type Assessment, type Question, type Option, type Attempt, type Submission, type QuizResult,
} from '@/lib/assessments'
import { coursePath, assessmentEditPath, type Scope } from '@/lib/paths'
import { friendlyError } from '@/lib/errors'
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'

const props = defineProps<{ orgId: string; assessmentId: string; scope: Scope }>()
const auth = useAuthStore()
const ws = useWorkspaceStore()

const a = ref<Assessment | null>(null)
const questions = ref<Question[]>([])
const options = ref<Option[]>([])
const attempts = ref<Attempt[]>([])
const answers = ref<Record<string, string>>({})
const result = ref<QuizResult | null>(null)
const submission = ref<Submission | null>(null)
const draft = ref('')
const loading = ref(true); const busy = ref(false)
const error = ref(''); const notice = ref('')

const uid = computed(() => auth.user?.id ?? '')
const optionsOf = (q: Question) => options.value.filter(o => o.question_id === q.id)
const attemptsLeft = computed(() => a.value?.max_attempts ? Math.max(0, a.value.max_attempts - attempts.value.length) : null)
const allAnswered = computed(() => questions.value.length > 0 && questions.value.every(q => answers.value[q.id]))
const canEdit = computed(() => ws.canIn(props.orgId, 'courses.manage') || ws.canIn(props.orgId, 'courses.create'))
const late = computed(() => !!(a.value?.due_at && submission.value && new Date(submission.value.submitted_at) > new Date(a.value.due_at)))
const pastDue = computed(() => !!(a.value?.due_at && new Date(a.value.due_at) < new Date()))

async function load() {
  loading.value = true; error.value = ''; result.value = null
  try {
    a.value = await getAssessment(props.assessmentId)
    if (!a.value) return
    if (a.value.kind === 'quiz') {
      const q = await loadQuiz(props.assessmentId)
      questions.value = q.questions; options.value = q.options
      attempts.value = await myAttempts(props.assessmentId, uid.value)
    } else {
      submission.value = await mySubmission(props.assessmentId, uid.value)
      draft.value = submission.value?.body ?? ''
    }
  } catch (e) { error.value = friendlyError(e) } finally { loading.value = false }
}
watch(() => props.assessmentId, load, { immediate: true })

async function submitQ() {
  busy.value = true; error.value = ''
  try {
    result.value = await submitQuiz(props.assessmentId, answers.value)
    attempts.value = await myAttempts(props.assessmentId, uid.value)
    answers.value = {}
  } catch (e) { error.value = friendlyError(e) } finally { busy.value = false }
}

async function submitWork() {
  error.value = ''; notice.value = ''
  if (!draft.value.trim()) { error.value = 'Write your answer first.'; return }
  busy.value = true
  try {
    await saveSubmission(props.orgId, a.value!.course_id, props.assessmentId, draft.value, submission.value)
    submission.value = await mySubmission(props.assessmentId, uid.value)
    notice.value = 'Submitted. You can revise it until it is graded.'
  } catch (e) { error.value = friendlyError(e) } finally { busy.value = false }
}
const fmt = (d: string) => new Date(d).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })
</script>

<template>
  <div class="max-w-3xl">
    <p v-if="loading" class="text-muted" role="status">Loading…</p>
    <div v-else-if="!a">
      <h1 class="text-2xl font-bold">Not available</h1>
      <p class="mt-2 text-muted">It may not exist, may not be published yet, or you may need to enrol in the course first.</p>
    </div>

    <template v-else>
      <RouterLink :to="coursePath(scope, a.course_id)" class="link text-sm">Back to course</RouterLink>
      <div class="mt-2 flex flex-wrap items-start justify-between gap-3">
        <h1 class="text-3xl font-bold">{{ a.title }}</h1>
        <BaseButton v-if="canEdit" variant="secondary" :to="assessmentEditPath(scope, a.course_id, a.id)">Edit</BaseButton>
      </div>
      <p v-if="a.status === 'draft'" class="mt-3 rounded-control bg-warn-soft px-3 py-2 text-sm text-warn">This is a draft. Learners cannot see it yet.</p>
      <p v-if="a.instructions" class="mt-3 max-w-prose whitespace-pre-line text-muted">{{ a.instructions }}</p>
      <p v-if="a.due_at" class="mt-2 text-sm" :class="pastDue ? 'text-warn' : 'text-muted'">Due {{ fmt(a.due_at) }}<span v-if="pastDue"> (past due; late work is still accepted)</span></p>
      <p v-if="error" role="alert" class="mt-4 rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>

      <!-- QUIZ -->
      <template v-if="a.kind === 'quiz'">
        <p class="mt-3 text-sm text-muted">Pass mark {{ a.pass_mark }}%<span v-if="attemptsLeft !== null"> · {{ attemptsLeft }} attempt{{ attemptsLeft === 1 ? '' : 's' }} left</span></p>

        <section v-if="result" class="panel mt-6 p-6" role="status" aria-live="polite">
          <h2 class="text-xl font-bold">{{ result.passed ? 'You passed' : 'Not passed yet' }}</h2>
          <p class="mt-1 text-2xl font-bold" :class="result.passed ? 'text-mint-text' : 'text-warn'">{{ result.score_percent }}%</p>
          <ul class="mt-4 space-y-1 text-sm">
            <li v-for="(q, i) in questions" :key="q.id">
              <span :class="result.results[q.id] ? 'text-mint-text' : 'text-danger'" aria-hidden="true">{{ result.results[q.id] ? '✓' : '✗' }}</span>
              Question {{ i + 1 }}: <span class="font-medium">{{ result.results[q.id] ? 'correct' : 'incorrect' }}</span>
            </li>
          </ul>
          <p class="mt-3 text-sm text-muted">Correct answers are not shown, so you can try again fairly.</p>
        </section>

        <form v-if="attemptsLeft !== 0 && a.status === 'published'" class="mt-6 space-y-6" @submit.prevent="submitQ">
          <fieldset v-for="(q, i) in questions" :key="q.id" class="panel p-5">
            <legend class="sr-only">Question {{ i + 1 }}</legend>
            <p class="font-medium"><span class="text-muted">{{ i + 1 }}.</span> {{ q.prompt }} <span class="text-sm text-muted">({{ q.points }} pt{{ q.points === 1 ? '' : 's' }})</span></p>
            <div class="mt-3 space-y-2">
              <label v-for="o in optionsOf(q)" :key="o.id" class="flex cursor-pointer items-start gap-3 rounded-control border border-line px-3 py-2 has-[:checked]:border-brand has-[:checked]:bg-brand-soft">
                <input v-model="answers[q.id]" type="radio" :name="`q-${q.id}`" :value="o.id" class="mt-1 h-4 w-4 accent-[rgb(var(--tv-brand))]" />
                <span>{{ o.label }}</span>
              </label>
            </div>
          </fieldset>
          <BaseButton type="submit" size="lg" :loading="busy" :disabled="!allAnswered">Submit answers</BaseButton>
          <p v-if="!allAnswered" class="text-sm text-muted">Answer every question to submit.</p>
        </form>
        <p v-else-if="attemptsLeft === 0" class="mt-6 rounded-control bg-sunken px-4 py-3 text-sm text-muted">You have used all your attempts.</p>

        <section v-if="attempts.length" class="mt-8">
          <h2 class="text-lg font-semibold">Your attempts</h2>
          <ul class="panel mt-3 divide-y divide-line text-sm">
            <li v-for="t in attempts" :key="t.id" class="flex justify-between gap-4 px-4 py-3">
              <span>Attempt {{ t.attempt_no }} · {{ fmt(t.submitted_at) }}</span>
              <span class="font-medium" :class="t.passed ? 'text-mint-text' : 'text-muted'">{{ t.score_percent }}% {{ t.passed ? '· passed' : '' }}</span>
            </li>
          </ul>
        </section>
      </template>

      <!-- ASSIGNMENT -->
      <template v-else>
        <p class="mt-3 text-sm text-muted">Worth {{ a.max_points }} points</p>

        <section v-if="submission?.status === 'graded'" class="panel mt-6 p-6" role="status">
          <h2 class="text-xl font-bold">Graded</h2>
          <p class="mt-1 text-2xl font-bold text-mint-text">{{ submission.points }} <span class="text-base font-normal text-muted">of {{ a.max_points }}</span></p>
          <template v-if="submission.feedback"><h3 class="mt-4 text-sm font-semibold">Feedback</h3><p class="mt-1 whitespace-pre-line">{{ submission.feedback }}</p></template>
          <h3 class="mt-4 text-sm font-semibold">Your submission</h3>
          <p class="mt-1 whitespace-pre-line text-muted">{{ submission.body }}</p>
        </section>

        <form v-else-if="a.status === 'published'" class="mt-6 space-y-4" @submit.prevent="submitWork">
          <BaseTextarea v-model="draft" label="Your answer" :rows="12" :maxlength="20000" />
          <p v-if="submission" class="text-sm text-muted">Submitted {{ fmt(submission.submitted_at) }}<span v-if="late" class="text-warn"> (late)</span>. Waiting for feedback. You can still revise it.</p>
          <p v-if="notice" role="status" class="rounded-control bg-brand-soft px-3 py-2 text-sm text-brand-strong">{{ notice }}</p>
          <BaseButton type="submit" size="lg" :loading="busy">{{ submission ? 'Update submission' : 'Submit' }}</BaseButton>
        </form>
      </template>
    </template>
  </div>
</template>
