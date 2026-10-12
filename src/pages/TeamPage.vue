<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import BaseField from '@/components/BaseField.vue'
import BaseSelect from '@/components/BaseSelect.vue'
import BaseButton from '@/components/BaseButton.vue'
import { supabase } from '@/lib/supabase'
import { friendlyError } from '@/lib/errors'
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'

interface Member { membership_id: string; user_id: string; full_name: string | null; email: string; role_key: string; role_name: string; status: 'invited' | 'active' | 'suspended' }
interface Invite { id: string; email: string; expires_at: string; roles: { name: string } | null }
interface Role { id: string; key: string; name: string }

const auth = useAuthStore()
const ws = useWorkspaceStore()
const members = ref<Member[]>([])
const invites = ref<Invite[]>([])
const roles = ref<Role[]>([])
const email = ref('')
const roleKey = ref('student')
const link = ref('')
const error = ref('')
const notice = ref('')
const busy = ref(false)
const loading = ref(true)

const ASSIGNABLE = ['admin', 'instructor', 'teaching_assistant', 'student']
const roleOptions = computed(() => roles.value.filter(r => ASSIGNABLE.includes(r.key)).map(r => ({ value: r.key, label: r.name })))
const canManage = computed(() => ws.can('members.manage'))

async function load() {
  if (!ws.activeId || !canManage.value) { loading.value = false; return }
  loading.value = true; error.value = ''
  try {
    const [m, i, r] = await Promise.all([
      supabase.rpc('list_members', { p_org: ws.activeId }),
      supabase.from('invitations').select('id, email, expires_at, roles(name)').eq('org_id', ws.activeId).eq('status', 'pending').order('created_at', { ascending: false }),
      supabase.from('roles').select('id, key, name').is('org_id', null),
    ])
    if (m.error) throw m.error; if (i.error) throw i.error; if (r.error) throw r.error
    members.value = (m.data as Member[]) ?? []
    invites.value = (i.data as unknown as Invite[]) ?? []
    roles.value = (r.data as Role[]) ?? []
  } catch (e) { error.value = friendlyError(e) } finally { loading.value = false }
}
watch(() => [ws.activeId, canManage.value], load, { immediate: true })

async function run(fn: () => Promise<void>) {
  busy.value = true; error.value = ''; notice.value = ''
  try { await fn(); await load() } catch (e) { error.value = friendlyError(e) } finally { busy.value = false }
}

const invite = () => run(async () => {
  link.value = ''
  const { data, error: err } = await supabase.rpc('create_invitation', { p_org: ws.activeId, p_email: email.value, p_role_key: roleKey.value })
  if (err) throw err
  link.value = `${location.origin}/invite/${data as string}`
  notice.value = `Invitation created for ${email.value.trim().toLowerCase()}.`
  email.value = ''
})
const revoke = (i: Invite) => run(async () => {
  const { error: err } = await supabase.rpc('revoke_invitation', { p_id: i.id })
  if (err) throw err
})
async function copy() {
  try { await navigator.clipboard.writeText(link.value); notice.value = 'Link copied.' } catch { notice.value = 'Select the link and copy it manually.' }
}

// Row Level Security filters rows silently, so an update that returns nothing was refused.
const changeRole = (m: Member, key: string) => run(async () => {
  const role = roles.value.find(r => r.key === key)
  if (!role) return
  const { data, error: err } = await supabase.from('memberships').update({ role_id: role.id }).eq('id', m.membership_id).select('id')
  if (err) throw err
  if (!data?.length) throw { code: '42501' }
})
const setStatus = (m: Member, status: 'active' | 'suspended') => run(async () => {
  const { data, error: err } = await supabase.from('memberships').update({ status }).eq('id', m.membership_id).select('id')
  if (err) throw err
  if (!data?.length) throw { code: '42501' }
})
const remove = (m: Member) => {
  if (!window.confirm(`Remove ${m.full_name || m.email} from this workspace?`)) return
  run(async () => {
    const { data, error: err } = await supabase.from('memberships').delete().eq('id', m.membership_id).select('id')
    if (err) throw err
    if (!data?.length) throw { code: '42501' }
  })
}
const isLocked = (m: Member) => m.role_key === 'owner' || m.user_id === auth.user?.id
const fmtDate = (d: string) => new Date(d).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })
</script>

<template>
  <div class="max-w-4xl">
    <h1 class="text-3xl font-bold">Team</h1>
    <p class="mt-2 text-muted">People in this workspace and their roles.</p>

    <p v-if="!canManage" role="status" class="mt-6 rounded-control bg-sunken px-4 py-3 text-sm text-muted">You do not have permission to manage the team.</p>

    <template v-else>
      <p v-if="error" role="alert" class="mt-4 rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
      <p v-if="notice" role="status" class="mt-4 rounded-control bg-brand-soft px-3 py-2 text-sm text-brand-strong">{{ notice }}</p>

      <section class="panel mt-8 p-6">
        <h2 class="text-lg font-semibold">Invite someone</h2>
        <form class="mt-4 grid gap-4 sm:grid-cols-[1fr_12rem_auto] sm:items-end" @submit.prevent="invite">
          <BaseField v-model="email" label="Email" type="email" required />
          <BaseSelect v-model="roleKey" label="Role" :options="roleOptions" />
          <BaseButton type="submit" :loading="busy">Create invitation</BaseButton>
        </form>
        <div v-if="link" class="mt-5 rounded-control bg-sunken p-4">
          <p class="text-sm font-medium">Send this link to the person</p>
          <div class="mt-2 flex gap-2">
            <input :value="link" readonly aria-label="Invitation link" class="h-10 min-w-0 flex-1 rounded-control border border-line bg-raised px-3 text-sm" @focus="($event.target as HTMLInputElement).select()" />
            <BaseButton variant="secondary" @click="copy">Copy</BaseButton>
          </div>
          <p class="mt-2 text-sm text-muted">Email delivery of invitations is not set up yet, so share the link yourself. It works once, only for the email address you entered, and expires in 14 days. It is shown only now.</p>
        </div>
      </section>

      <section v-if="invites.length" class="mt-8">
        <h2 class="text-lg font-semibold">Pending invitations</h2>
        <ul class="panel mt-3 divide-y divide-line">
          <li v-for="i in invites" :key="i.id" class="flex flex-wrap items-center justify-between gap-3 px-4 py-3 text-sm">
            <div class="min-w-0"><p class="truncate font-medium">{{ i.email }}</p><p class="text-muted">{{ i.roles?.name }} · expires {{ fmtDate(i.expires_at) }}</p></div>
            <BaseButton variant="ghost" :disabled="busy" @click="revoke(i)">Revoke</BaseButton>
          </li>
        </ul>
      </section>

      <section class="mt-8">
        <h2 class="text-lg font-semibold">Members</h2>
        <p v-if="loading" class="mt-3 text-muted" role="status">Loading…</p>
        <div v-else class="panel mt-3 overflow-x-auto">
          <table class="w-full min-w-[36rem] text-left text-sm">
            <thead class="border-b border-line text-muted">
              <tr><th scope="col" class="px-4 py-3 font-medium">Person</th><th scope="col" class="px-4 py-3 font-medium">Role</th><th scope="col" class="px-4 py-3 font-medium">Status</th><th scope="col" class="px-4 py-3"><span class="sr-only">Actions</span></th></tr>
            </thead>
            <tbody class="divide-y divide-line">
              <tr v-for="m in members" :key="m.membership_id">
                <td class="px-4 py-3"><p class="font-medium">{{ m.full_name || m.email }}</p><p v-if="m.full_name" class="text-muted">{{ m.email }}</p></td>
                <td class="px-4 py-3">
                  <span v-if="isLocked(m)">{{ m.role_name }}</span>
                  <select v-else :value="m.role_key" :aria-label="`Role for ${m.full_name || m.email}`" class="h-9 rounded-control border border-line bg-raised px-2" :disabled="busy" @change="changeRole(m, ($event.target as HTMLSelectElement).value)">
                    <option v-for="o in roleOptions" :key="o.value" :value="o.value">{{ o.label }}</option>
                  </select>
                </td>
                <td class="px-4 py-3 capitalize">{{ m.status }}</td>
                <td class="px-4 py-3 text-right">
                  <span v-if="!isLocked(m)" class="inline-flex gap-1">
                    <BaseButton variant="ghost" :disabled="busy" @click="setStatus(m, m.status === 'active' ? 'suspended' : 'active')">{{ m.status === 'active' ? 'Suspend' : 'Reactivate' }}</BaseButton>
                    <BaseButton variant="ghost" :disabled="busy" @click="remove(m)">Remove</BaseButton>
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>
  </div>
</template>
