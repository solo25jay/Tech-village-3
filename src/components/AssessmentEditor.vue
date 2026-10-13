<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import BaseField from '@/components/BaseField.vue'
import BaseTextarea from '@/components/BaseTextarea.vue'
import BaseButton from '@/components/BaseButton.vue'
import {
  getAssessment, updateAssessment, deleteAssessment, loadQuiz, loadKeys, addQuestion, updateQuestion, deleteQuestion,
  addOption, updateOption, deleteOption, setKey, type Assessment, type Question, type Option,
} from '@/lib/assessments'
import { courseEditPath, assessmentPath, assessmentReviewPath, type Scope } from '@/lib/paths'
import { friendlyError } from '@/lib/errors'

const props = defineProps<{ orgId: string; assessmentId: string; scope: Scope }>()
const router = useRouter()

const a = ref<Assessment | null>(null)
const questions = ref<Question[]>([])
const options = ref<Option[]>([])
const keys = ref<Record<string, string>>({})
const title = ref(''); const instructions = ref('')
const passMark = ref('70'); const maxAttempts = ref(''); const maxPoints = ref('100'); const dueAt = ref('')
const newQuestion = ref('')
const newOption = ref<Record<string, string>>({})
const loading = ref(true); const busy = ref(false)
const error = ref(''); const notice = ref('')

const locked = computed(() => a.value?.status === 'published')
const isQuiz = computed(() => a.value?.kind === 'quiz')
const optionsOf = (q: Question) => options.value.filter(o => o.question_id === q.id)

// <input type="datetime-local"> works in local time, the database stores UTC
const toLocalInput = (iso: string | null) => iso ? new Date(new Date(iso).getTime() - new Date(iso).getTimezoneOffset() * 60000).toISOString().slice(0, 16) : ''

async function reloadQuiz() {
  const q = await loadQuiz(props.assessmentId)
  questions.value = q.questions; options.value = q.options
  keys.value = await loadKeys(props.assessmentId)
}
async function load() {
  loading.value = true; error.value = ''
  try {
    a.value = await getAssessment(props.assessmentId)
    if (!a.value) return
    title.value = a.value.title; instructions.value = a.value.instructions ?? ''
    passMark.value = String(a.value.pass_mark); maxAttempts.value = a.value.max_attempts ? String(a.value.max_attempts) : ''
    maxPoints.value = String(a.value.max_points); dueAt.value = toLocalInput(a.value.due_at)
    if (a.value.kind === 'quiz') await reloadQuiz()
  } catch (e) { error.value = friendlyError(e) } finally { loading.value = false }
}
watch(() => props.assessmentId, load, { immediate: true })

async function run(fn: () => Promise<void>, reload: 'none' | 'quiz' | 'all' = 'quiz') {
  busy.value = true; error.value = ''; notice.value = ''
  try {
    await fn()
    if (reload === 'all') a.value = await getAssessment(props.assessmentId)
    if (isQuiz.value && reload !== 'none') await reloadQuiz()
  } catch (e) { error.value = friendlyError(e); try { if (isQuiz.value) await reloadQuiz() } catch { /* ignore */ } }
  finally { busy.value = false }
}

const intOrNull = (v: string) => (v.trim() === '' ? null : Number.parseInt(v, 10))

const saveDetails = () => run(async () => {
  if (title.value.trim().length < 2) throw { message: 'The title needs at least 2 characters.' }
  const patch: Parameters<typeof updateAssessment>[1] = {
    title: title.value.trim(), instructions: instructions.value.trim() || null,
    due_at: dueAt.value ? new Date(dueAt.value).toISOString() : null,
  }
  if (isQuiz.value) {
    const pm = intOrNull(passMark.value); const ma = intOrNull(maxAttempts.value)
    if (pm === null || pm < 1 || pm > 100) throw { message: 'The pass mark must be between 1 and 100.' }
    if (ma !== null && (ma < 1 || ma > 20)) throw { message: 'Attempts must be between 1 and 20, or left empty for unlimited.' }
    patch.pass_mark = pm; patch.max_attempts = ma
  } else {
    const mp = intOrNull(maxPoints.value)
    if (mp === null || mp < 1 || mp > 1000) throw { message: 'Maximum points must be between 1 and 1000.' }
    patch.max_points = mp
  }
  await updateAssessment(props.assessmentId, patch)
  notice.value = 'Saved.'
}, 'all')

// The database refuses to publish an incomplete quiz and shows why.
const setStatus = (status: 'draft' | 'published') => run(async () => {
  await updateAssessment(props.assessmentId, { status })
  notice.value = status === 'published' ? 'Published. Enrolled learners can see it now.' : 'Unpublished. Questions can be edited again.'
}, 'all')

const remove = () => {
  if (!a.value || !window.confirm('Delete this assessment, including all attempts or submissions? This cannot be undone.')) return
  const courseId = a.value.course_id
  run(async () => { await deleteAssessment(props.assessmentId); router.push(courseEditPath(props.scope, courseId)) }, 'none')
}

const submitQuestion = () => run(async () => {
  if (!newQuestion.value.trim()) throw { message: 'Write the question first.' }
  await addQuestion(props.orgId, a.value!.course_id, props.assessmentId, newQuestion.value, questions.value)
  newQuestion.value = ''
})
const submitOption = (q: Question) => run(async () => {
  const label = (newOption.value[q.id] ?? '').trim()
  if (!label) throw { message: 'Write the answer option first.' }
  await addOption(props.orgId, a.value!.course_id, props.assessmentId, q.id, label, options.value)
  newOption.value[q.id] = ''
})
const saveQuestion = (q: Question) => run(async () => {
  if (!q.prompt.trim()) throw { message: 'A question cannot be empty.' }
  if (!(q.points >= 1 && q.points <= 100)) throw { message: 'Points must be between 1 and 100.' }
  await updateQuestion(q.id, { prompt: q.prompt.trim(), points: q.points })
  notice.value = 'Question saved.'
})
const saveOption = (o: Option, label: string) => run(async () => {
  if (!label.trim()) throw { message: 'An option cannot be empty.' }
  await updateOption(o.id, label)
})
const markCorrect = (q: Question, o: Option) => run(() => setKey(props.orgId, a.value!.course_id, props.assessmentId, q.id, o.id))
const removeQuestion = (q: Question) => { if (window.confirm('Delete this question and its options?')) run(() => deleteQuestion(q.id)) }
const removeOption = (o: Option) => run(() => deleteOption(o.id))
</script>

<template>
  <div class="max-w-4xl">
    <p v-if="loading" class="text-muted" role="status">Loading…</p>
    <div v-else-if="!a">
      <h1 class="text-2xl font-bold">Assessment not found</h1>
      <p class="mt-2 text-muted">It may not exist, or you may not be allowed to edit it.</p>
    </div>

    <template v-else>
      <RouterLink :to="courseEditPath(scope, a.course_id)" class="link text-sm">Back to course editor</RouterLink>
      <div class="mt-2 flex flex-wrap items-center gap-3">
        <h1 class="text-3xl font-bold">Edit {{ isQuiz ? 'quiz' : 'assignment' }}</h1>
        <span class="rounded-full px-2.5 py-1 text-xs font-semibold capitalize" :class="locked ? 'bg-brand-soft text-brand' : 'bg-warn-soft text-warn'">{{ a.status }}</span>
      </div>
      <p v-if="error" role="alert" class="mt-4 rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
      <p v-if="notice" role="status" class="mt-4 rounded-control bg-brand-soft px-3 py-2 text-sm text-brand-strong">{{ notice }}</p>

      <section class="panel mt-6 space-y-4 p-6">
        <h2 class="text-lg font-semibold">Details</h2>
        <BaseField v-model="title" label="Title" required :minlength="2" />
        <BaseTextarea v-model="instructions" label="Instructions" :rows="4" :maxlength="5000" hint="Optional. Shown to learners before they start." />
        <div class="grid gap-4 sm:grid-cols-3">
          <template v-if="isQuiz">
            <BaseField v-model="passMark" label="Pass mark (%)" type="number" />
            <BaseField v-model="maxAttempts" label="Attempts allowed" type="number" hint="Leave empty for unlimited." />
          </template>
          <BaseField v-else v-model="maxPoints" label="Maximum points" type="number" />
          <BaseField v-model="dueAt" label="Due date" type="datetime-local" hint="Optional. Late work is still accepted and shown as late." />
        </div>
        <div class="flex flex-wrap gap-2">
          <BaseButton :loading="busy" @click="saveDetails">Save details</BaseButton>
          <BaseButton v-if="!locked" variant="secondary" :disabled="busy" @click="setStatus('published')">Publish</BaseButton>
          <BaseButton v-else variant="secondary" :disabled="busy" @click="setStatus('draft')">Unpublish</BaseButton>
          <BaseButton variant="secondary" :to="assessmentPath(scope, a.course_id, a.id)">Preview</BaseButton>
          <BaseButton variant="secondary" :to="assessmentReviewPath(scope, a.course_id, a.id)">{{ isQuiz ? 'Results' : 'Submissions' }}</BaseButton>
          <BaseButton variant="danger" :disabled="busy" @click="remove">Delete</BaseButton>
        </div>
      </section>

      <section v-if="isQuiz" class="mt-8" aria-labelledby="q-h">
        <h2 id="q-h" class="text-lg font-semibold">Questions</h2>
        <p v-if="locked" class="mt-3 rounded-control bg-warn-soft px-4 py-3 text-sm text-warn">
          This quiz is published, so its questions are locked. Unpublish it to make changes. Earlier attempts are kept.
        </p>
        <p v-else class="mt-2 text-sm text-muted">Each question needs at least two options and one marked correct. Learners never see which one is correct.</p>

        <div v-for="(q, qi) in questions" :key="q.id" class="panel mt-4 p-4">
          <div class="flex items-start gap-3">
            <span class="mt-2 font-display font-bold text-muted">{{ qi + 1 }}.</span>
            <div class="min-w-0 flex-1 space-y-3">
              <BaseTextarea :model-value="q.prompt" label="Question" :rows="2" :maxlength="1000" @update:model-value="(v: string) => { q.prompt = v }" />
              <div class="flex items-end gap-3">
                <div class="w-28"><BaseField :model-value="String(q.points)" label="Points" type="number" :disabled="locked" @update:model-value="(v: string) => { q.points = Number(v) }" /></div>
                <BaseButton variant="secondary" :disabled="busy || locked" @click="saveQuestion(q)">Save question</BaseButton>
                <BaseButton variant="ghost" :disabled="busy || locked" @click="removeQuestion(q)">Delete</BaseButton>
              </div>
              <fieldset>
                <legend class="text-sm font-medium">Options. Select the correct one.</legend>
                <ul class="mt-2 space-y-2">
                  <li v-for="o in optionsOf(q)" :key="o.id" class="flex items-center gap-2">
                    <input type="radio" :name="`key-${q.id}`" :checked="keys[q.id] === o.id" :disabled="busy || locked" :aria-label="`Mark correct: ${o.label}`" class="h-4 w-4 accent-[rgb(var(--tv-brand))]" @change="markCorrect(q, o)" />
                    <input :value="o.label" :aria-label="`Option text: ${o.label}`" maxlength="500" :disabled="locked" class="h-9 min-w-0 flex-1 rounded-control border border-line bg-raised px-3 text-sm focus:border-brand disabled:bg-sunken"
                           @change="saveOption(o, ($event.target as HTMLInputElement).value)" />
                    <button type="button" class="grid h-8 w-8 place-items-center rounded-control text-danger hover:bg-danger-soft disabled:opacity-40" :disabled="busy || locked" :aria-label="`Delete option ${o.label}`" @click="removeOption(o)">✕</button>
                  </li>
                </ul>
                <p v-if="!keys[q.id] && optionsOf(q).length" class="mt-2 text-sm text-warn">No correct answer selected yet.</p>
                <form v-if="!locked" class="mt-3 flex gap-2" @submit.prevent="submitOption(q)">
                  <label class="sr-only" :for="`no-${q.id}`">New option</label>
                  <input :id="`no-${q.id}`" v-model="newOption[q.id]" placeholder="Add an option" maxlength="500" class="h-9 min-w-0 flex-1 rounded-control border border-line bg-raised px-3 text-sm focus:border-brand" />
                  <BaseButton type="submit" variant="secondary" :disabled="busy">Add option</BaseButton>
                </form>
              </fieldset>
            </div>
          </div>
        </div>

        <form v-if="!locked" class="panel mt-4 flex flex-wrap items-end gap-3 p-4" @submit.prevent="submitQuestion">
          <div class="min-w-[16rem] flex-1"><BaseField v-model="newQuestion" label="New question" /></div>
          <BaseButton type="submit" :disabled="busy">Add question</BaseButton>
        </form>
      </section>
    </template>
  </div>
</template>
