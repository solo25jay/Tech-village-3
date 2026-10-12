<script setup lang="ts">
import { ref, reactive, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import BaseField from '@/components/BaseField.vue'
import BaseTextarea from '@/components/BaseTextarea.vue'
import BaseButton from '@/components/BaseButton.vue'
import LessonContent from '@/components/LessonContent.vue'
import {
  getCourse, updateCourse, deleteCourse, loadOutline, addModule, renameModule, deleteModule, addLesson, renameLesson,
  deleteLesson, swapPositions, loadBlocks, addBlock, updateBlock, deleteBlock,
  type Course, type CourseStatus, type ModuleRow, type LessonRow, type BlockRow,
} from '@/lib/courses'
import { parseVideoUrl } from '@/lib/video'
import { coursePath, coursesPath, type Scope } from '@/lib/paths'
import { friendlyError } from '@/lib/errors'

const props = defineProps<{ orgId: string; courseId: string; scope: Scope }>()
const router = useRouter()

const course = ref<Course | null>(null)
const title = ref('')
const summary = ref('')
const modules = ref<ModuleRow[]>([])
const lessons = ref<LessonRow[]>([])
const blocks = ref<BlockRow[]>([])
const selectedId = ref<string | null>(null)
const blockEdits = reactive<Record<string, string>>({})
const newModule = ref('')
const newLesson = reactive<Record<string, string>>({})
const newText = ref('')
const newVideo = ref('')
const loading = ref(true)
const busy = ref(false)
const error = ref('')
const notice = ref('')

const selected = computed(() => lessons.value.find(l => l.id === selectedId.value) ?? null)
const lessonsOf = (m: ModuleRow) => lessons.value.filter(l => l.module_id === m.id)

async function reloadOutline() {
  const o = await loadOutline(props.courseId)
  modules.value = o.modules; lessons.value = o.lessons
  if (selectedId.value && !lessons.value.some(l => l.id === selectedId.value)) selectedId.value = null
}
async function reloadBlocks() {
  if (!selectedId.value) { blocks.value = []; return }
  blocks.value = await loadBlocks(selectedId.value)
  for (const b of blocks.value) blockEdits[b.id] = (b.block_type === 'text' ? b.body : b.video_url) ?? ''
}
async function load() {
  loading.value = true; error.value = ''
  try {
    course.value = await getCourse(props.courseId)
    if (course.value) { title.value = course.value.title; summary.value = course.value.summary ?? ''; await reloadOutline() }
  } catch (e) { error.value = friendlyError(e) } finally { loading.value = false }
}
watch(() => props.courseId, load, { immediate: true })
watch(selectedId, () => run(reloadBlocks, false))

/** Runs an action with a busy flag and shows any error. Optionally reloads the outline afterwards. */
async function run(fn: () => Promise<void>, refresh = true) {
  busy.value = true; error.value = ''; notice.value = ''
  try { await fn(); if (refresh) await reloadOutline() } catch (e) { error.value = friendlyError(e); try { await reloadOutline() } catch { /* ignore */ } }
  finally { busy.value = false }
}

// ---- course details and status ----
const saveDetails = () => run(async () => {
  if (title.value.trim().length < 2) throw { message: 'The title needs at least 2 characters.' }
  await updateCourse(props.courseId, { title: title.value.trim(), summary: summary.value.trim() || null })
  course.value = await getCourse(props.courseId); notice.value = 'Saved.'
})
const setStatus = (status: CourseStatus) => run(async () => {
  if (status === 'published' && !lessons.value.length) throw { message: 'Add at least one lesson before publishing.' }
  if (status === 'archived' && !window.confirm('Archive this course? It disappears from the course list.')) return
  await updateCourse(props.courseId, { status })
  course.value = await getCourse(props.courseId)
  notice.value = status === 'published' ? 'Published. Learners can now enrol.' : status === 'draft' ? 'Unpublished. Only editors can see it.' : 'Archived.'
  if (status === 'archived') router.push(coursesPath(props.scope))
})
const removeCourse = () => {
  if (!window.confirm('Delete this course permanently, including its lessons, enrolments and progress? This cannot be undone.')) return
  run(async () => { await deleteCourse(props.courseId); router.push(coursesPath(props.scope)) }, false)
}

// ---- outline ----
const submitModule = () => run(async () => {
  if (!newModule.value.trim()) throw { message: 'Give the module a title.' }
  await addModule(props.orgId, props.courseId, newModule.value, modules.value); newModule.value = ''
})
const submitLesson = (m: ModuleRow) => run(async () => {
  const t = (newLesson[m.id] ?? '').trim()
  if (!t) throw { message: 'Give the lesson a title.' }
  selectedId.value = await addLesson(props.orgId, props.courseId, m.id, t, lessons.value); newLesson[m.id] = ''
})
const removeModule = (m: ModuleRow) => { if (window.confirm(`Delete the module “${m.title}” and all its lessons?`)) run(() => deleteModule(m.id)) }
const removeLesson = (l: LessonRow) => { if (window.confirm(`Delete the lesson “${l.title}”?`)) run(() => deleteLesson(l.id)) }
function move<T extends { id: string; position: number }>(table: 'modules' | 'lessons' | 'lesson_blocks', list: T[], item: T, dir: -1 | 1, after: () => Promise<void>) {
  const sorted = [...list].sort((a, b) => a.position - b.position)
  const j = sorted.findIndex(x => x.id === item.id) + dir
  if (j < 0 || j >= sorted.length) return
  run(async () => { await swapPositions(table, item, sorted[j]); await after() }, false)
}

// ---- blocks ----
const addText = () => run(async () => {
  if (!newText.value.trim()) throw { message: 'Write some text first.' }
  await addBlock(props.orgId, props.courseId, selectedId.value!, 'text', { body: newText.value.trim() }, blocks.value)
  newText.value = ''; await reloadBlocks()
}, false)
const addVideoBlock = () => run(async () => {
  const v = parseVideoUrl(newVideo.value)
  if (!v) throw { message: 'Use a YouTube or Vimeo link (https).' }
  await addBlock(props.orgId, props.courseId, selectedId.value!, 'video', { video_url: v.canonical }, blocks.value)
  newVideo.value = ''; await reloadBlocks()
}, false)
const saveBlock = (b: BlockRow) => run(async () => {
  const value = (blockEdits[b.id] ?? '').trim()
  if (b.block_type === 'text') {
    if (!value) throw { message: 'Text cannot be empty. Delete the block instead.' }
    await updateBlock(b.id, { body: value })
  } else {
    const v = parseVideoUrl(value)
    if (!v) throw { message: 'Use a YouTube or Vimeo link (https).' }
    await updateBlock(b.id, { video_url: v.canonical })
  }
  await reloadBlocks(); notice.value = 'Block saved.'
}, false)
const removeBlock = (b: BlockRow) => run(async () => { await deleteBlock(b.id); await reloadBlocks() }, false)
</script>

<template>
  <div>
    <p v-if="loading" class="text-muted" role="status">Loading…</p>
    <div v-else-if="!course" class="max-w-xl">
      <h1 class="text-2xl font-bold">Course not found</h1>
      <p class="mt-2 text-muted">It may not exist, or you may not be allowed to edit it.</p>
      <RouterLink :to="coursesPath(scope)" class="link mt-4 inline-block">Back to courses</RouterLink>
    </div>

    <template v-else>
      <RouterLink :to="coursePath(scope, course.id)" class="link text-sm">Preview as learner</RouterLink>
      <div class="mt-2 flex flex-wrap items-center gap-3">
        <h1 class="text-3xl font-bold">Edit course</h1>
        <span class="rounded-full px-2.5 py-1 text-xs font-semibold capitalize" :class="course.status === 'published' ? 'bg-brand-soft text-brand' : 'bg-warn-soft text-warn'">{{ course.status }}</span>
      </div>

      <p v-if="error" role="alert" class="mt-4 rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
      <p v-if="notice" role="status" class="mt-4 rounded-control bg-brand-soft px-3 py-2 text-sm text-brand-strong">{{ notice }}</p>

      <section class="panel mt-6 space-y-4 p-6">
        <h2 class="text-lg font-semibold">Details</h2>
        <BaseField v-model="title" label="Title" required :minlength="2" />
        <BaseTextarea v-model="summary" label="Summary" :maxlength="500" />
        <div class="flex flex-wrap gap-2">
          <BaseButton :loading="busy" @click="saveDetails">Save details</BaseButton>
          <BaseButton v-if="course.status !== 'published'" variant="secondary" :disabled="busy" @click="setStatus('published')">Publish</BaseButton>
          <BaseButton v-else variant="secondary" :disabled="busy" @click="setStatus('draft')">Unpublish</BaseButton>
          <BaseButton variant="ghost" :disabled="busy" @click="setStatus('archived')">Archive</BaseButton>
          <BaseButton variant="danger" :disabled="busy" @click="removeCourse">Delete course</BaseButton>
        </div>
      </section>

      <div class="mt-8 grid gap-8 lg:grid-cols-[22rem_1fr]">
        <!-- Outline -->
        <section aria-labelledby="outline-h">
          <h2 id="outline-h" class="text-lg font-semibold">Modules and lessons</h2>
          <p v-if="!modules.length" class="mt-3 text-sm text-muted">Start by adding a module, such as “Getting started”.</p>
          <div v-for="m in modules" :key="m.id" class="panel mt-4 p-4">
            <div class="flex items-center gap-1">
              <input :value="m.title" :aria-label="`Module title: ${m.title}`" maxlength="160" class="h-9 min-w-0 flex-1 rounded-control border border-transparent bg-transparent px-2 font-display font-semibold hover:border-line focus:border-brand"
                     @change="run(() => renameModule(m.id, ($event.target as HTMLInputElement).value))" />
              <button type="button" class="grid h-8 w-8 place-items-center rounded-control hover:bg-sunken" :aria-label="`Move ${m.title} up`" @click="move('modules', modules, m, -1, reloadOutline)">↑</button>
              <button type="button" class="grid h-8 w-8 place-items-center rounded-control hover:bg-sunken" :aria-label="`Move ${m.title} down`" @click="move('modules', modules, m, 1, reloadOutline)">↓</button>
              <button type="button" class="grid h-8 w-8 place-items-center rounded-control text-danger hover:bg-danger-soft" :aria-label="`Delete module ${m.title}`" @click="removeModule(m)">✕</button>
            </div>
            <ul class="mt-2 space-y-1">
              <li v-for="l in lessonsOf(m)" :key="l.id" class="flex items-center gap-1">
                <button type="button" class="min-w-0 flex-1 truncate rounded-control px-3 py-2 text-left text-sm hover:bg-sunken" :class="l.id === selectedId && 'bg-brand-soft font-medium text-brand'"
                        :aria-current="l.id === selectedId ? 'true' : undefined" @click="selectedId = l.id">{{ l.title }}</button>
                <button type="button" class="grid h-8 w-8 place-items-center rounded-control hover:bg-sunken" :aria-label="`Move ${l.title} up`" @click="move('lessons', lessonsOf(m), l, -1, reloadOutline)">↑</button>
                <button type="button" class="grid h-8 w-8 place-items-center rounded-control hover:bg-sunken" :aria-label="`Move ${l.title} down`" @click="move('lessons', lessonsOf(m), l, 1, reloadOutline)">↓</button>
                <button type="button" class="grid h-8 w-8 place-items-center rounded-control text-danger hover:bg-danger-soft" :aria-label="`Delete lesson ${l.title}`" @click="removeLesson(l)">✕</button>
              </li>
            </ul>
            <form class="mt-3 flex gap-2" @submit.prevent="submitLesson(m)">
              <label class="sr-only" :for="`nl-${m.id}`">New lesson title</label>
              <input :id="`nl-${m.id}`" v-model="newLesson[m.id]" placeholder="New lesson title" maxlength="160" class="h-9 min-w-0 flex-1 rounded-control border border-line bg-raised px-3 text-sm focus:border-brand" />
              <BaseButton type="submit" variant="secondary" :disabled="busy">Add</BaseButton>
            </form>
          </div>
          <form class="mt-4 flex gap-2" @submit.prevent="submitModule">
            <label class="sr-only" for="new-module">New module title</label>
            <input id="new-module" v-model="newModule" placeholder="New module title" maxlength="160" class="h-10 min-w-0 flex-1 rounded-control border border-line bg-raised px-3 text-sm focus:border-brand" />
            <BaseButton type="submit" :disabled="busy">Add module</BaseButton>
          </form>
        </section>

        <!-- Lesson content -->
        <section aria-labelledby="content-h" class="min-w-0">
          <h2 id="content-h" class="text-lg font-semibold">{{ selected ? selected.title : 'Lesson content' }}</h2>
          <p v-if="!selected" class="mt-3 text-sm text-muted">Select a lesson to add text and videos. You can mix both in one lesson.</p>

          <template v-else>
            <ul class="mt-4 space-y-4">
              <li v-for="b in [...blocks].sort((x, y) => x.position - y.position)" :key="b.id" class="panel p-4">
                <div class="flex items-center justify-between gap-2">
                  <span class="text-xs font-semibold uppercase tracking-wide text-muted">{{ b.block_type === 'text' ? 'Text' : 'Video' }}</span>
                  <span class="flex gap-1">
                    <button type="button" class="grid h-8 w-8 place-items-center rounded-control hover:bg-sunken" aria-label="Move block up" @click="move('lesson_blocks', blocks, b, -1, reloadBlocks)">↑</button>
                    <button type="button" class="grid h-8 w-8 place-items-center rounded-control hover:bg-sunken" aria-label="Move block down" @click="move('lesson_blocks', blocks, b, 1, reloadBlocks)">↓</button>
                    <button type="button" class="grid h-8 w-8 place-items-center rounded-control text-danger hover:bg-danger-soft" aria-label="Delete block" @click="removeBlock(b)">✕</button>
                  </span>
                </div>
                <div class="mt-2">
                  <BaseTextarea v-if="b.block_type === 'text'" v-model="blockEdits[b.id]" label="Text" :rows="6" :maxlength="20000" hint="Leave a blank line between paragraphs." />
                  <BaseField v-else v-model="blockEdits[b.id]" label="Video link" type="url" placeholder="https://www.youtube.com/watch?v=…" />
                </div>
                <BaseButton class="mt-3" variant="secondary" :disabled="busy" @click="saveBlock(b)">Save block</BaseButton>
              </li>
            </ul>

            <div class="mt-6 grid gap-4 md:grid-cols-2">
              <form class="panel space-y-3 p-4" @submit.prevent="addText">
                <BaseTextarea v-model="newText" label="Add a text block" :rows="4" :maxlength="20000" />
                <BaseButton type="submit" variant="secondary" :disabled="busy">Add text</BaseButton>
              </form>
              <form class="panel space-y-3 p-4" @submit.prevent="addVideoBlock">
                <BaseField v-model="newVideo" label="Add a video block" type="url" placeholder="https://youtu.be/…" hint="YouTube or Vimeo." />
                <BaseButton type="submit" variant="secondary" :disabled="busy">Add video</BaseButton>
              </form>
            </div>

            <h3 class="mt-10 text-sm font-semibold uppercase tracking-wide text-muted">What learners will see</h3>
            <div class="mt-4 rounded-panel border border-line p-5"><LessonContent :blocks="blocks" /></div>
          </template>
        </section>
      </div>
    </template>
  </div>
</template>
