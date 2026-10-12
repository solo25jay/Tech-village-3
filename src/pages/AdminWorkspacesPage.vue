<script setup lang="ts">
import { ref, onMounted } from 'vue'
import BaseButton from '@/components/BaseButton.vue'
import { supabase } from '@/lib/supabase'
import { friendlyError } from '@/lib/errors'
import { ORG_TYPE_LABELS, type OrgType } from '@/types/domain'

interface Row {
  org_id: string; name: string; workspace_name: string; slug: string; org_type: OrgType
  status: 'active' | 'suspended'; created_at: string; plan_name: string | null
  subscription_status: string | null; member_count: number
}
const rows = ref<Row[]>([])
const loading = ref(true)
const error = ref('')
const busyId = ref<string | null>(null)

async function load() {
  loading.value = true; error.value = ''
  const { data, error: err } = await supabase.rpc('admin_list_workspaces')
  if (err) error.value = friendlyError(err)
  rows.value = (data as Row[] | null) ?? []
  loading.value = false
}

async function toggle(r: Row) {
  const next = r.status === 'active' ? 'suspended' : 'active'
  const verb = next === 'suspended' ? 'Suspend' : 'Reactivate'
  if (!window.confirm(`${verb} “${r.workspace_name}”? ${next === 'suspended' ? 'Its members will lose access until it is reactivated.' : ''}`)) return
  busyId.value = r.org_id; error.value = ''
  try {
    const { error: err } = await supabase.rpc('admin_set_workspace_status', { p_org: r.org_id, p_status: next })
    if (err) throw err
    await load()
  } catch (e) { error.value = friendlyError(e) } finally { busyId.value = null }
}
onMounted(load)
</script>

<template>
  <div>
    <h1 class="text-3xl font-bold">Customer workspaces</h1>
    <p class="mt-2 max-w-prose text-muted">
      Every independent LMS on the platform. You can see status, plan and member counts. Students, courses and other private workspace data are not visible here.
    </p>

    <p v-if="error" role="alert" class="mt-4 rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
    <p v-if="loading" class="mt-8 text-muted" role="status">Loading…</p>
    <p v-else-if="!rows.length" class="panel mt-8 p-6 text-sm text-muted">No customer workspaces yet.</p>

    <div v-else class="panel mt-8 overflow-x-auto">
      <table class="w-full min-w-[40rem] text-left text-sm">
        <thead class="border-b border-line text-muted">
          <tr>
            <th scope="col" class="px-4 py-3 font-medium">Workspace</th>
            <th scope="col" class="px-4 py-3 font-medium">Type</th>
            <th scope="col" class="px-4 py-3 font-medium">Plan</th>
            <th scope="col" class="px-4 py-3 font-medium">Members</th>
            <th scope="col" class="px-4 py-3 font-medium">Status</th>
            <th scope="col" class="px-4 py-3"><span class="sr-only">Actions</span></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-line">
          <tr v-for="r in rows" :key="r.org_id">
            <td class="px-4 py-3"><p class="font-medium">{{ r.workspace_name }}</p><p class="text-muted">{{ r.name }} · {{ r.slug }}</p></td>
            <td class="px-4 py-3">{{ ORG_TYPE_LABELS[r.org_type] }}</td>
            <td class="px-4 py-3">{{ r.plan_name ?? 'None' }}<span v-if="r.subscription_status" class="block text-muted capitalize">{{ r.subscription_status }}</span></td>
            <td class="px-4 py-3">{{ r.member_count }}</td>
            <td class="px-4 py-3"><span class="rounded-full px-2.5 py-1 text-xs font-semibold" :class="r.status === 'active' ? 'bg-brand-soft text-brand' : 'bg-warn-soft text-warn'">{{ r.status === 'active' ? 'Active' : 'Suspended' }}</span></td>
            <td class="px-4 py-3 text-right">
              <BaseButton :variant="r.status === 'active' ? 'secondary' : 'primary'" :loading="busyId === r.org_id" @click="toggle(r)">
                {{ r.status === 'active' ? 'Suspend' : 'Reactivate' }}
              </BaseButton>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
