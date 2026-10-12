<script setup lang="ts">
import { computed } from 'vue'
import CourseList from '@/components/CourseList.vue'
import { useWorkspaceStore } from '@/stores/workspace'
import type { Scope } from '@/lib/paths'

const props = defineProps<{ scope: Scope }>()
const ws = useWorkspaceStore()
const orgId = computed(() => (props.scope === 'official' ? ws.official?.org_id : ws.activeId) ?? null)
</script>

<template>
  <div class="max-w-5xl">
    <h1 class="text-3xl font-bold">{{ scope === 'official' ? 'Tech Village courses' : 'Courses' }}</h1>
    <p class="mb-8 mt-2 text-muted">{{ scope === 'official' ? 'Official courses from Tech Village.' : 'Courses in this workspace.' }}</p>
    <CourseList v-if="orgId" :org-id="orgId" :scope="scope" />
  </div>
</template>
