<script setup lang="ts">
import { ref, watch } from 'vue'
import BaseField from '@/components/BaseField.vue'
import BaseSelect from '@/components/BaseSelect.vue'
import BaseTextarea from '@/components/BaseTextarea.vue'
import BaseButton from '@/components/BaseButton.vue'
import { supabase } from '@/lib/supabase'
import { friendlyError } from '@/lib/errors'
import { uploadOrgLogo, validateLogo } from '@/lib/storage'
import { useWorkspaceStore } from '@/stores/workspace'
import { ORG_TYPE_LABELS, type OrgType, type OrganisationDetails } from '@/types/domain'

const ws = useWorkspaceStore()
const org = ref<OrganisationDetails | null>(null)
const form = ref({ name: '', workspace_name: '', org_type: 'other' as OrgType, description: '', country: '', contact_email: '', contact_phone: '', website: '' })
const error = ref('')
const success = ref('')
const busy = ref(false)
const logoBusy = ref(false)
const typeOptions = Object.entries(ORG_TYPE_LABELS).map(([value, label]) => ({ value, label }))

watch(() => ws.activeId, async (id) => {
  org.value = null
  if (!id) return
  const { data } = await supabase.from('organisations')
    .select('id, name, workspace_name, slug, org_type, description, country, contact_email, contact_phone, website, logo_url')
    .eq('id', id).maybeSingle()
  org.value = data as OrganisationDetails | null
  if (org.value) form.value = {
    name: org.value.name, workspace_name: org.value.workspace_name, org_type: org.value.org_type,
    description: org.value.description ?? '', country: org.value.country ?? '',
    contact_email: org.value.contact_email ?? '', contact_phone: org.value.contact_phone ?? '', website: org.value.website ?? '',
  }
}, { immediate: true })

async function save() {
  if (!org.value) return
  error.value = ''; success.value = ''
  const f = form.value
  if (f.website.trim() && !/^https?:\/\/\S+$/i.test(f.website.trim())) { error.value = 'Website must start with http:// or https://'; return }
  busy.value = true
  try {
    const { error: err, data } = await supabase.from('organisations').update({
      name: f.name.trim(), workspace_name: f.workspace_name.trim(), org_type: f.org_type,
      description: f.description.trim() || null, country: f.country.trim() || null,
      contact_email: f.contact_email.trim() || null, contact_phone: f.contact_phone.trim() || null,
      website: f.website.trim() || null,
    }).eq('id', org.value.id).select('id')
    if (err) throw err
    // RLS filters rows silently, so zero rows back means the server refused the change.
    if (!data?.length) throw { code: '42501' }
    success.value = 'Saved.'
    await ws.load()
  } catch (e) { error.value = friendlyError(e) } finally { busy.value = false }
}

async function onLogo(e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (!file || !org.value) return
  error.value = ''; success.value = ''
  const problem = validateLogo(file)
  if (problem) { error.value = problem; return }
  logoBusy.value = true
  try {
    const url = await uploadOrgLogo(org.value.id, file)
    const { error: err, data } = await supabase.from('organisations').update({ logo_url: url }).eq('id', org.value.id).select('id')
    if (err) throw err
    if (!data?.length) throw { code: '42501' }
    org.value.logo_url = url
    success.value = 'Logo updated.'
    await ws.load()
  } catch (er) { error.value = friendlyError(er) } finally { logoBusy.value = false }
}
</script>

<template>
  <div class="max-w-2xl">
    <h1 class="text-3xl font-bold">Organisation settings</h1>
    <p class="mt-2 text-muted">These details belong to your workspace only.</p>

    <p v-if="!ws.can('org.manage')" role="status" class="mt-6 rounded-control bg-sunken px-4 py-3 text-sm text-muted">You do not have permission to edit these settings.</p>

    <div v-else-if="org" class="mt-8 space-y-8">
      <section class="panel p-6">
        <h2 class="text-lg font-semibold">Logo</h2>
        <div class="mt-4 flex items-center gap-4">
          <img v-if="org.logo_url" :src="org.logo_url" alt="Current logo" class="h-16 w-16 rounded-md border border-line object-cover" />
          <div v-else class="grid h-16 w-16 place-items-center rounded-md bg-brand-soft font-display text-xl font-bold text-brand">{{ org.workspace_name.slice(0, 1).toUpperCase() }}</div>
          <div v-if="ws.can('org.branding')">
            <label for="logo" class="sr-only">Upload a new logo</label>
            <input id="logo" type="file" accept="image/png,image/jpeg,image/webp" :disabled="logoBusy" class="text-sm file:mr-3 file:rounded-control file:border-0 file:bg-brand-soft file:px-4 file:py-2 file:font-semibold file:text-brand" @change="onLogo" />
            <p class="mt-1.5 text-sm text-muted">PNG, JPEG or WebP, up to 2 MB.</p>
          </div>
        </div>
      </section>

      <form class="panel space-y-5 p-6" @submit.prevent="save">
        <h2 class="text-lg font-semibold">Details</h2>
        <BaseField v-model="form.name" label="Organisation name" required :minlength="2" />
        <BaseField v-model="form.workspace_name" label="Workspace name" required :minlength="2" />
        <BaseField :model-value="org.slug" label="Workspace address" hint="The address is fixed after creation." disabled />
        <BaseSelect v-model="form.org_type" label="Organisation type" :options="typeOptions" />
        <BaseTextarea v-model="form.description" label="Description" :maxlength="1000" />
        <div class="grid gap-5 sm:grid-cols-2">
          <BaseField v-model="form.country" label="Country" autocomplete="country-name" />
          <BaseField v-model="form.website" label="Website" type="url" placeholder="https://" />
          <BaseField v-model="form.contact_email" label="Contact email" type="email" />
          <BaseField v-model="form.contact_phone" label="Contact phone" type="tel" />
        </div>
        <p v-if="error" role="alert" class="rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
        <p v-if="success" role="status" class="rounded-control bg-brand-soft px-3 py-2 text-sm text-brand-strong">{{ success }}</p>
        <BaseButton type="submit" :loading="busy">Save changes</BaseButton>
      </form>
    </div>
  </div>
</template>
