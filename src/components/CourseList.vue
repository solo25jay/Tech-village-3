<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import BaseField from '@/components/BaseField.vue'
import BaseTextarea from '@/components/BaseTextarea.vue'
import BaseButton from '@/components/BaseButton.vue'
import { listCourses, createCourse, enrol, myEnrolledCourseIds, type Course } from '@/lib/courses'
import { coursePath, courseEditPath, type Scope } from '@/lib/paths'
import { friendlyError } from '@/lib/errors'
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'

const props = defineProps<{ orgId: string; scope: Scope }>()
const auth = useAuthStore()
const ws = useWorkspaceStore()
const router = useRouter()

const courses = ref<Course[]>([])
const enrolled = ref<Set<string>>(new Set())
const loading = ref(true)
const error = ref('')
const newTitle = ref('')
const newSummary = ref('')
const creating = ref(false)
const enrollingId = ref<string | null>(null)

const canCreate = computed(() => ws.canIn(props.orgId, 'courses.create'))
const canEdit = (c: Course) =>
  ws.canIn(props.orgId, 'courses.manage') || (ws.canIn(props.orgId, 'courses.create') && c.created_by === auth.user?.id)

async function load() {
  loading.value = true; error.value = ''
  try {
    const uid = auth.user?.id
    const [list, mine] = await Promise.all([listCourses(props.orgId), uid ? myEnrolledCourseIds(props.orgId, uid) : Promise.resolve(new Set<string>())])
    courses.value = list; enrolled.value = mine
  } catch (e) { error.value = friendlyError(e) } finally { loading.value = false }
}
watch(() => props.orgId, load, { immediate: true })

async function create() {
  error.value = ''
  if (newTitle.value.trim().length < 2) { error.value = 'Give the course a title of at least 2 characters.'; return }
  creating.value = true
  try {
    const id = await createCourse(props.orgId, newTitle.value, newSummary.value)
    router.push(courseEditPath(props.scope, id))
  } catch (e) { error.value = friendlyError(e) } finally { creating.value = false }
}

async function join(c: Course) {
  if (!auth.user) return
  enrollingId.value = c.id; error.value = ''
  try { await enrol(props.orgId, c.id, auth.user.id); await load() }
  catch (e) { error.value = friendlyError(e) } finally { enrollingId.value = null }
}
</script>

<template>
  <div>
    <p v-if="error" role="alert" class="mb-4 rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>

    <section v-if="canCreate" class="panel mb-8 p-6">
      <h2 class="text-lg font-semibold">New course</h2>
      <p class="mt-1 text-sm text-muted">New courses start as drafts. Only you and people who manage courses can see a draft.</p>
      <form class="mt-4 space-y-4" @submit.prevent="create">
        <BaseField v-model="newTitle" label="Title" required :minlength="2" />
        <BaseTextarea v-model="newSummary" label="Summary" :maxlength="500" hint="Optional. A sentence or two for the course list." />
        <BaseButton type="submit" :loading="creating">Create course</BaseButton>
      </form>
    </section>

    <p v-if="loading" class="text-muted" role="status">Loading courses…</p>
    <p v-else-if="!courses.length" class="panel p-6 text-sm text-muted">
      {{ canCreate ? 'No courses yet. Create the first one above.' : 'There are no published courses yet. Check back soon.' }}
    </p>

    <ul v-else class="grid gap-4 md:grid-cols-2">
      <li v-for="c in courses" :key="c.id" class="panel flex flex-col p-6">
        <div class="flex items-start justify-between gap-3">
          <h3 class="font-display text-lg font-semibold">{{ c.title }}</h3>
          <span v-if="c.status !== 'published'" class="shrink-0 rounded-full bg-warn-soft px-2.5 py-1 text-xs font-semibold text-warn">Draft</span>
          <span v-else-if="enrolled.has(c.id)" class="shrink-0 rounded-full bg-brand-soft px-2.5 py-1 text-xs font-semibold text-brand">Enrolled</span>
        </div>
        <p v-if="c.summary" class="mt-2 text-sm text-muted">{{ c.summary }}</p>
        <div class="mt-auto flex flex-wrap gap-2 pt-5">
          <BaseButton v-if="c.status === 'published' && enrolled.has(c.id)" :to="coursePath(scope, c.id)">Continue</BaseButton>
          <BaseButton v-else-if="c.status === 'published'" :loading="enrollingId === c.id" @click="join(c)">Enrol</BaseButton>
          <BaseButton v-if="c.status === 'published' && !enrolled.has(c.id)" variant="secondary" :to="coursePath(scope, c.id)">Details</BaseButton>
          <BaseButton v-if="canEdit(c)" variant="secondary" :to="courseEditPath(scope, c.id)">Edit</BaseButton>
        </div>
      </li>
    </ul>
  </div>
</template>
