<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import CourseEditor from '@/components/CourseEditor.vue'
import { useWorkspaceStore } from '@/stores/workspace'
import type { Scope } from '@/lib/paths'

const props = defineProps<{ scope: Scope }>()
const route = useRoute()
const ws = useWorkspaceStore()
const orgId = computed(() => (props.scope === 'official' ? ws.official?.org_id : ws.activeId) ?? null)
const courseId = computed(() => String(route.params.courseId))
</script>

<template>
  <CourseEditor v-if="orgId" :key="courseId" :org-id="orgId" :course-id="courseId" :scope="scope" />
</template>
