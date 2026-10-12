<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { useWorkspaceStore } from '@/stores/workspace'

const ws = useWorkspaceStore()
const open = ref(false)
const container = ref<HTMLElement | null>(null)

function onDocClick(e: MouseEvent) {
  if (container.value && !container.value.contains(e.target as Node)) open.value = false
}
function onKey(e: KeyboardEvent) { if (e.key === 'Escape') open.value = false }
onMounted(() => { document.addEventListener('click', onDocClick); document.addEventListener('keydown', onKey) })
onBeforeUnmount(() => { document.removeEventListener('click', onDocClick); document.removeEventListener('keydown', onKey) })

async function pick(id: string) {
  await ws.switchTo(id)
  open.value = false
}
</script>

<template>
  <div ref="container" class="relative">
    <component :is="ws.workspaces.length > 1 ? 'button' : 'div'" type="button"
               class="flex w-full items-center gap-3 rounded-control border border-line bg-raised px-3 py-2 text-left"
               :class="ws.workspaces.length > 1 && 'hover:bg-sunken'"
               :aria-haspopup="ws.workspaces.length > 1 ? 'listbox' : undefined" :aria-expanded="ws.workspaces.length > 1 ? open : undefined"
               @click="ws.workspaces.length > 1 && (open = !open)">
      <img v-if="ws.active?.logo_url" :src="ws.active.logo_url" alt="" class="h-9 w-9 shrink-0 rounded-md object-cover" />
      <span v-else class="grid h-9 w-9 shrink-0 place-items-center rounded-md bg-brand-soft font-display text-sm font-bold text-brand">
        {{ ws.active?.workspace_name.slice(0, 1).toUpperCase() ?? '?' }}
      </span>
      <span class="min-w-0 flex-1">
        <span class="block truncate text-sm font-semibold">{{ ws.active?.workspace_name }}</span>
        <span class="block truncate text-xs text-muted">{{ ws.active?.role_name }}</span>
      </span>
      <svg v-if="ws.workspaces.length > 1" class="h-4 w-4 shrink-0 text-muted" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="m7 15 5 5 5-5M7 9l5-5 5 5" /></svg>
    </component>

    <!-- Only shown when the person belongs to more than one customer workspace (for example, staff at two schools). -->
    <div v-if="open" role="listbox" class="panel absolute left-0 right-0 z-30 mt-2 max-h-80 overflow-auto p-1.5">
      <button v-for="w in ws.workspaces" :key="w.org_id" type="button" role="option" :aria-selected="w.org_id === ws.activeId"
              class="flex w-full items-center justify-between rounded-md px-3 py-2 text-left text-sm hover:bg-sunken"
              :class="w.org_id === ws.activeId && 'bg-brand-soft'" @click="pick(w.org_id)">
        <span class="truncate font-medium">{{ w.workspace_name }}</span>
        <span class="ml-2 shrink-0 text-xs text-muted">{{ w.role_name }}</span>
      </button>
    </div>
  </div>
</template>
