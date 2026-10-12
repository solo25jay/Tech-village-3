<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '@/lib/supabase'
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'
import { ORG_TYPE_LABELS, type OrganisationDetails } from '@/types/domain'

const auth = useAuthStore()
const ws = useWorkspaceStore()
const route = useRoute()

interface Sub { status: string; trial_ends_at: string | null; plans: { name: string } | null }
const org = ref<OrganisationDetails | null>(null)
const subscription = ref<Sub | null>(null)

watch(() => [ws.activeId, ws.permsByOrg] as const, async () => {
  org.value = null; subscription.value = null
  if (!ws.activeId) return
  const { data } = await supabase.from('organisations')
    .select('id, name, workspace_name, slug, org_type, description, country, contact_email, contact_phone, website, logo_url')
    .eq('id', ws.activeId).maybeSingle()
  org.value = data as OrganisationDetails | null
  // Billing details are only requested if the role includes billing.manage; RLS enforces this anyway.
  if (ws.can('billing.manage')) {
    const { data: sub } = await supabase.from('subscriptions')
      .select('status, trial_ends_at, plans(name)').eq('org_id', ws.activeId).maybeSingle()
    subscription.value = sub as unknown as Sub | null
  }
}, { immediate: true })

// Every item below reflects real data in the organisation record.
const checklist = computed(() => !org.value ? [] : [
  { label: 'Add your logo', done: !!org.value.logo_url },
  { label: 'Describe your organisation', done: !!org.value.description },
  { label: 'Add contact details', done: !!(org.value.contact_phone || org.value.website) },
])
const doneCount = computed(() => checklist.value.filter(i => i.done).length)

const trialEnds = () => subscription.value?.trial_ends_at
  ? new Date(subscription.value.trial_ends_at).toLocaleDateString(undefined, { day: 'numeric', month: 'long', year: 'numeric' })
  : null
</script>

<template>
  <div class="max-w-4xl">
    <h1 class="text-3xl font-bold">{{ ws.active?.workspace_name }}</h1>
    <p class="mt-2 text-muted">
      Welcome, {{ auth.displayName.split(' ')[0] }}. You are the {{ ws.active?.role_name?.toLowerCase() }} of this workspace.
    </p>

    <p v-if="route.query.logo === 'failed'" role="status" class="mt-4 rounded-control bg-warn-soft px-4 py-3 text-sm text-warn">
      Your workspace was created, but the logo could not be uploaded. You can add it in Organisation settings.
    </p>

    <div class="mt-8 grid gap-4 md:grid-cols-2">
      <section class="panel p-6">
        <h2 class="text-lg font-semibold">Organisation</h2>
        <dl v-if="org" class="mt-4 space-y-3 text-sm">
          <div class="flex justify-between gap-4"><dt class="text-muted">Name</dt><dd class="text-right font-medium">{{ org.name }}</dd></div>
          <div class="flex justify-between gap-4"><dt class="text-muted">Type</dt><dd class="font-medium">{{ ORG_TYPE_LABELS[org.org_type] }}</dd></div>
          <div class="flex justify-between gap-4"><dt class="text-muted">Address</dt><dd class="font-medium">{{ org.slug }}</dd></div>
        </dl>
      </section>

      <section v-if="subscription" class="panel p-6">
        <h2 class="text-lg font-semibold">Plan</h2>
        <p class="mt-4 text-2xl font-bold">{{ subscription.plans?.name }}</p>
        <p class="mt-1 text-sm capitalize text-muted">{{ subscription.status }}<span v-if="trialEnds()"> until {{ trialEnds() }}</span></p>
        <p class="mt-3 text-sm text-muted">Payment setup arrives with the billing phase.</p>
      </section>
    </div>

    <section v-if="org" class="panel mt-4 p-6">
      <div class="flex items-baseline justify-between gap-4">
        <h2 class="text-lg font-semibold">Set up your workspace</h2>
        <p class="text-sm text-muted">{{ doneCount }} of {{ checklist.length }} done</p>
      </div>
      <ul class="mt-4 space-y-3">
        <li v-for="item in checklist" :key="item.label" class="flex items-center gap-3 text-sm">
          <span class="grid h-5 w-5 shrink-0 place-items-center rounded-full border" :class="item.done ? 'border-mint-text bg-mint-text text-white' : 'border-line'" aria-hidden="true">
            <svg v-if="item.done" class="h-3 w-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3"><path stroke-linecap="round" stroke-linejoin="round" d="m5 12 5 5 9-10" /></svg>
          </span>
          <span :class="item.done && 'text-muted line-through'">{{ item.label }}</span>
          <span class="sr-only">{{ item.done ? 'completed' : 'not completed' }}</span>
        </li>
      </ul>
      <RouterLink v-if="ws.can('org.manage') && doneCount < checklist.length" :to="{ name: 'settings' }" class="link mt-5 inline-block text-sm">Open organisation settings</RouterLink>
      <p class="mt-5 border-t border-line pt-4 text-sm text-muted">
        You can already create courses and invite your team. Assignments, assessments and certificates arrive in later phases.
      </p>
    </section>
  </div>
</template>
