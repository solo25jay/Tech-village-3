<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import BaseButton from '@/components/BaseButton.vue'
import LessonContent from '@/components/LessonContent.vue'
import {
  getCourse, loadOutline, loadBlocks, enrol, withdraw, completedLessonIds, markComplete, unmarkComplete,
  myEnrolledCourseIds, type Course, type ModuleRow, type LessonRow, type BlockRow,
} from '@/lib/courses'
import { coursesPath, courseEditPath, type Scope } from '@/lib/paths'
import { friendlyError } from '@/lib/errors'
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'

const props = defineProps<{ orgId: string; courseId: string; scope: Scope }>()
const auth = useAuthStore()
const ws = useWorkspaceStore()

const course = ref<Course | null>(null)
const modules = ref<ModuleRow[]>([])
const lessons = ref<LessonRow[]>([])
const blocks = ref<BlockRow[]>([])
const completed = ref<Set<string>>(new Set())
const enrolled = ref(false)
const selectedId = ref<string | null>(null)
const loading = ref(true)
const blocksLoading = ref(false)
const busy = ref(false)
const error = ref('')

const uid = computed(() => auth.user?.id ?? '')
const isEditor = computed(() => !!course.value && (
  ws.canIn(props.orgId, 'courses.manage') || (ws.canIn(props.orgId, 'courses.create') && course.value.created_by === uid.value)))
const canLearn = computed(() => enrolled.value && course.value?.status === 'published')
const canSeeContent = computed(() => canLearn.value || isEditor.value)
const selected = computed(() => lessons.value.find(l => l.id === selectedId.value) ?? null)
const progress = computed(() => lessons.value.length ? Math.round((lessons.value.filter(l => completed.value.has(l.id)).length / lessons.value.length) * 100) : 0)
const lessonsOf = (m: ModuleRow) => lessons.value.filter(l => l.module_id === m.id)

async function load() {
  loading.value = true; error.value = ''
  try {
    course.value = await getCourse(props.courseId)
    if (!course.value) return
    enrolled.value = (await myEnrolledCourseIds(props.orgId, uid.value)).has(props.courseId)
    if (canSeeContent.value) {
      const o = await loadOutline(props.courseId)
      modules.value = o.modules; lessons.value = o.lessons
      completed.value = await completedLessonIds(props.courseId, uid.value)
      selectedId.value = lessons.value.find(l => !completed.value.has(l.id))?.id ?? lessons.value[0]?.id ?? null
    }
  } catch (e) { error.value = friendlyError(e) } finally { loading.value = false }
}
watch(() => [props.courseId, props.orgId], load, { immediate: true })

watch(selectedId, async (id) => {
  blocks.value = []
  if (!id) return
  blocksLoading.value = true
  try { blocks.value = await loadBlocks(id) } catch (e) { error.value = friendlyError(e) } finally { blocksLoading.value = false }
})

async function run(fn: () => Promise<void>) {
  busy.value = true; error.value = ''
  try { await fn() } catch (e) { error.value = friendlyError(e) } finally { busy.value = false }
}
const join = () => run(async () => { await enrol(props.orgId, props.courseId, uid.value); await load() })
const leave = () => { if (window.confirm('Withdraw from this course? Your progress is kept if you rejoin.')) run(async () => { await withdraw(props.courseId, uid.value); await load() }) }
const toggleDone = () => run(async () => {
  if (!selected.value) return
  const id = selected.value.id
  if (completed.value.has(id)) { await unmarkComplete(id, uid.value); completed.value.delete(id) }
  else { await markComplete(props.orgId, props.courseId, id, uid.value); completed.value.add(id) }
  completed.value = new Set(completed.value)
})
</script>

<template>
  <div>
    <p v-if="loading" class="text-muted" role="status">Loading…</p>

    <div v-else-if="!course" class="max-w-xl">
      <h1 class="text-2xl font-bold">Course not available</h1>
      <p class="mt-2 text-muted">It may not exist, may not be published yet, or may belong to a different workspace.</p>
      <RouterLink :to="coursesPath(scope)" class="link mt-4 inline-block">Back to courses</RouterLink>
    </div>

    <template v-else>
      <RouterLink :to="coursesPath(scope)" class="link text-sm">All courses</RouterLink>
      <div class="mt-2 flex flex-wrap items-start justify-between gap-4">
        <div class="min-w-0">
          <h1 class="text-3xl font-bold">{{ course.title }}</h1>
          <p v-if="course.summary" class="mt-2 max-w-prose text-muted">{{ course.summary }}</p>
        </div>
        <BaseButton v-if="isEditor" variant="secondary" :to="courseEditPath(scope, course.id)">Edit course</BaseButton>
      </div>

      <p v-if="error" role="alert" class="mt-4 rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
      <p v-if="course.status !== 'published'" class="mt-4 rounded-control bg-warn-soft px-3 py-2 text-sm text-warn">This course is a draft. Only people who manage it can see it.</p>

      <section v-if="!canSeeContent" class="panel mt-8 max-w-xl p-6">
        <h2 class="text-lg font-semibold">Enrol to start learning</h2>
        <p class="mt-2 text-sm text-muted">Lessons are available to enrolled learners.</p>
        <BaseButton class="mt-4" :loading="busy" @click="join">Enrol in this course</BaseButton>
      </section>

      <div v-else class="mt-8 grid gap-8 lg:grid-cols-[18rem_1fr]">
        <nav aria-label="Course outline" class="space-y-5">
          <div v-if="canLearn">
            <div class="flex justify-between text-sm"><span class="font-medium">Progress</span><span class="text-muted">{{ progress }}%</span></div>
            <div class="mt-1.5 h-2 overflow-hidden rounded-full bg-sunken" role="progressbar" :aria-valuenow="progress" aria-valuemin="0" aria-valuemax="100" aria-label="Course progress">
              <div class="h-full bg-brand transition-all" :style="{ width: progress + '%' }" />
            </div>
          </div>
          <p v-if="!modules.length" class="text-sm text-muted">No lessons have been added yet.</p>
          <div v-for="m in modules" :key="m.id">
            <h2 class="font-display text-sm font-semibold">{{ m.title }}</h2>
            <ul class="mt-2 space-y-1">
              <li v-for="l in lessonsOf(m)" :key="l.id">
                <button type="button" class="flex w-full items-center gap-2 rounded-control px-3 py-2 text-left text-sm hover:bg-sunken"
                        :class="l.id === selectedId && 'bg-brand-soft font-medium text-brand'" :aria-current="l.id === selectedId ? 'true' : undefined" @click="selectedId = l.id">
                  <span class="grid h-4 w-4 shrink-0 place-items-center rounded-full border text-[10px]" :class="completed.has(l.id) ? 'border-mint-text bg-mint-text text-white' : 'border-line'" aria-hidden="true">
                    <template v-if="completed.has(l.id)">✓</template>
                  </span>
                  <span class="min-w-0 flex-1 truncate">{{ l.title }}</span>
                  <span v-if="completed.has(l.id)" class="sr-only">completed</span>
                </button>
              </li>
            </ul>
          </div>
          <BaseButton v-if="canLearn" variant="ghost" :loading="busy" @click="leave">Withdraw from course</BaseButton>
        </nav>

        <article class="min-w-0">
          <template v-if="selected">
            <h2 class="text-2xl font-bold">{{ selected.title }}</h2>
            <p v-if="blocksLoading" class="mt-6 text-muted" role="status">Loading lesson…</p>
            <div v-else class="mt-6"><LessonContent :blocks="blocks" /></div>
            <div v-if="canLearn && !blocksLoading" class="mt-10 border-t border-line pt-6">
              <BaseButton :variant="completed.has(selected.id) ? 'secondary' : 'primary'" :loading="busy" @click="toggleDone">
                {{ completed.has(selected.id) ? 'Completed. Mark as not done' : 'Mark lesson complete' }}
              </BaseButton>
            </div>
          </template>
          <p v-else class="text-muted">Select a lesson to begin.</p>
        </article>
      </div>
    </template>
  </div>
</template>
