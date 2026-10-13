<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import BaseField from '@/components/BaseField.vue'
import BaseSelect from '@/components/BaseSelect.vue'
import BaseButton from '@/components/BaseButton.vue'
import { listAssessments, createAssessment, myCourseStatus, type Assessment, type AssessmentKind } from '@/lib/assessments'
import { assessmentPath, assessmentEditPath, assessmentReviewPath, type Scope } from '@/lib/paths'
import { friendlyError } from '@/lib/errors'
import { useAuthStore } from '@/stores/auth'

/** mode "editor": create and manage (drafts included). mode "learner": published work with my status. */
const props = defineProps<{ orgId: string; courseId: string; scope: Scope; mode: 'editor' | 'learner' }>()
const auth = useAuthStore()
const router = useRouter()

const items = ref<Assessment[]>([])
const best = ref(new Map<string, { score: number; passed: boolean; attempts: number }>())
const subs = ref(new Map<string, { status: string; points: number | null }>())
const loading = ref(true)
const error = ref('')
const kind = ref<AssessmentKind>('quiz')
const title = ref('')
const creating = ref(false)
const kindOptions = [{ value: 'quiz', label: 'Quiz (graded automatically)' }, { value: 'assignment', label: 'Assignment (graded by you)' }]

const visible = computed(() => props.mode === 'editor' ? items.value : items.value.filter(a => a.status === 'published'))

async function load() {
  loading.value = true; error.value = ''
  try {
    items.value = await listAssessments(props.courseId)
    if (props.mode === 'learner' && auth.user) {
      const s = await myCourseStatus(props.courseId, auth.user.id)
      best.value = s.best; subs.value = s.subs
    }
  } catch (e) { error.value = friendlyError(e) } finally { loading.value = false }
}
watch(() => props.courseId, load, { immediate: true })

async function create() {
  error.value = ''
  if (title.value.trim().length < 2) { error.value = 'Give the assessment a title of at least 2 characters.'; return }
  creating.value = true
  try {
    const id = await createAssessment(props.orgId, props.courseId, kind.value, title.value, items.value)
    router.push(assessmentEditPath(props.scope, props.courseId, id))
  } catch (e) { error.value = friendlyError(e) } finally { creating.value = false }
}

function statusText(a: Assessment): string {
  if (a.kind === 'quiz') {
    const b = best.value.get(a.id)
    if (!b) return 'Not attempted'
    return `Best score ${b.score}% · ${b.passed ? 'passed' : 'not passed yet'} · ${b.attempts} attempt${b.attempts === 1 ? '' : 's'}`
  }
  const s = subs.value.get(a.id)
  if (!s) return 'Not submitted'
  return s.status === 'graded' ? `Graded: ${s.points} of ${a.max_points}` : 'Submitted, waiting for feedback'
}
const due = (a: Assessment) => a.due_at ? `Due ${new Date(a.due_at).toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })}` : ''
</script>

<template>
  <section aria-labelledby="assess-h">
    <h2 id="assess-h" class="text-lg font-semibold">Quizzes and assignments</h2>
    <p v-if="error" role="alert" class="mt-3 rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
    <p v-if="loading" class="mt-3 text-muted" role="status">Loading…</p>
    <p v-else-if="!visible.length" class="mt-3 text-sm text-muted">{{ mode === 'editor' ? 'None yet. Add a quiz or an assignment below.' : 'This course has no quizzes or assignments yet.' }}</p>

    <ul v-else class="panel mt-3 divide-y divide-line">
      <li v-for="a in visible" :key="a.id" class="flex flex-wrap items-center justify-between gap-3 px-4 py-3">
        <div class="min-w-0">
          <p class="truncate font-medium">
            {{ a.title }}
            <span class="ml-2 rounded-full bg-sunken px-2 py-0.5 text-xs font-semibold text-muted">{{ a.kind === 'quiz' ? 'Quiz' : 'Assignment' }}</span>
            <span v-if="mode === 'editor' && a.status === 'draft'" class="ml-1 rounded-full bg-warn-soft px-2 py-0.5 text-xs font-semibold text-warn">Draft</span>
          </p>
          <p class="text-sm text-muted">{{ mode === 'learner' ? statusText(a) : (a.kind === 'quiz' ? `Pass mark ${a.pass_mark}%` : `${a.max_points} points`) }}<span v-if="due(a)"> · {{ due(a) }}</span></p>
        </div>
        <div class="flex gap-2">
          <BaseButton v-if="mode === 'learner'" :to="assessmentPath(scope, courseId, a.id)">{{ a.kind === 'quiz' ? 'Open quiz' : 'Open' }}</BaseButton>
          <template v-else>
            <BaseButton variant="secondary" :to="assessmentEditPath(scope, courseId, a.id)">Edit</BaseButton>
            <BaseButton variant="secondary" :to="assessmentReviewPath(scope, courseId, a.id)">{{ a.kind === 'quiz' ? 'Results' : 'Submissions' }}</BaseButton>
          </template>
        </div>
      </li>
    </ul>

    <form v-if="mode === 'editor'" class="panel mt-4 grid gap-4 p-4 sm:grid-cols-[14rem_1fr_auto] sm:items-end" @submit.prevent="create">
      <BaseSelect v-model="kind" label="Type" :options="kindOptions" />
      <BaseField v-model="title" label="Title" required :minlength="2" />
      <BaseButton type="submit" :loading="creating">Add</BaseButton>
    </form>
  </section>
</template>
