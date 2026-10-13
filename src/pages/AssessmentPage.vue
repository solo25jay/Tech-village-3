<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import AssessmentTaker from '@/components/AssessmentTaker.vue'
import { useWorkspaceStore } from '@/stores/workspace'
import type { Scope } from '@/lib/paths'

const props = defineProps<{ scope: Scope }>()
const route = useRoute()
const ws = useWorkspaceStore()
const orgId = computed(() => (props.scope === 'official' ? ws.official?.org_id : ws.activeId) ?? null)
const assessmentId = computed(() => String(route.params.assessmentId))
</script>

<template>
  <AssessmentTaker v-if="orgId" :key="assessmentId" :org-id="orgId" :assessment-id="assessmentId" :scope="scope" />
</template>
