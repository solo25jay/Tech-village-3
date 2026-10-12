<script setup lang="ts">
import { ref, computed, watch, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import BaseField from '@/components/BaseField.vue'
import BaseSelect from '@/components/BaseSelect.vue'
import BaseTextarea from '@/components/BaseTextarea.vue'
import BaseButton from '@/components/BaseButton.vue'
import SetupNotice from '@/components/SetupNotice.vue'
import { supabase, isSupabaseConfigured } from '@/lib/supabase'
import { friendlyError, slugify } from '@/lib/errors'
import { uploadOrgLogo, validateLogo } from '@/lib/storage'
import { useAuthStore } from '@/stores/auth'
import { useWorkspaceStore } from '@/stores/workspace'
import { ORG_TYPE_LABELS, type OrgType } from '@/types/domain'

type Step = 'plan' | 'account' | 'organisation' | 'workspace'
interface PlanRow {
  key: string; name: string; description: string | null
  price_month_minor: number; currency: string; trial_days: number
  plan_entitlements: { key: string; value: { limit?: number; enabled?: boolean } }[]
}

const auth = useAuthStore()
const ws = useWorkspaceStore()
const route = useRoute()
const router = useRouter()

// ---- state ----
const step = ref<Step>('plan')
const plans = ref<PlanRow[]>([])
const plansLoaded = ref(false)
const planKey = ref('starter')

const fullName = ref('')
const email = ref('')
const password = ref('')

const orgName = ref('')
const orgType = ref<OrgType>('training_academy')
const description = ref('')
const country = ref('')
const contactEmail = ref('')
const contactPhone = ref('')
const website = ref('')

const workspaceName = ref('')
const slug = ref('')
const slugTouched = ref(false)
const logoFile = ref<File | null>(null)
const logoPreview = ref('')

const error = ref('')
const busy = ref(false)
const verifySent = ref(false)

// ---- derived ----
const signedIn = computed(() => auth.isAuthenticated)
const steps = computed<Step[]>(() => signedIn.value
  ? ['plan', 'organisation', 'workspace']
  : ['plan', 'account', 'organisation', 'workspace'])
const stepLabels: Record<Step, string> = { plan: 'Plan', account: 'Your account', organisation: 'Organisation', workspace: 'Workspace' }
const stepIndex = computed(() => steps.value.indexOf(step.value))
const selectedPlan = computed(() => plans.value.find(p => p.key === planKey.value))
const orgTypeOptions = Object.entries(ORG_TYPE_LABELS).map(([value, label]) => ({ value, label }))

watch(workspaceName, (n) => { if (!slugTouched.value) slug.value = slugify(n) })
watch(logoFile, (f) => {
  if (logoPreview.value) URL.revokeObjectURL(logoPreview.value)
  logoPreview.value = f ? URL.createObjectURL(f) : ''
})

// ---- helpers ----
function price(p: PlanRow) {
  if (!p.price_month_minor) return 'Free'
  return `${new Intl.NumberFormat('en-NG', { style: 'currency', currency: p.currency, maximumFractionDigits: 0 }).format(p.price_month_minor / 100)} per month`
}
function highlights(p: PlanRow): string[] {
  const get = (k: string) => p.plan_entitlements.find(e => e.key === k)?.value
  const out: string[] = []
  const students = get('max_students')?.limit; if (students) out.push(`Up to ${students.toLocaleString()} students`)
  const courses = get('max_courses')?.limit; if (courses) out.push(`${courses.toLocaleString()} courses`)
  const storage = get('storage_mb')?.limit; if (storage) out.push(`${storage >= 1000 ? `${storage / 1000} GB` : `${storage} MB`} storage`)
  if (get('coding_labs')?.enabled) out.push('Coding labs')
  if (get('custom_branding')?.enabled) out.push('Custom branding')
  return out
}
function fail(msg: string) { error.value = msg; return false }

// ---- step navigation ----
async function next() {
  error.value = ''
  if (step.value === 'plan') {
    if (!selectedPlan.value) return fail('Choose a plan to continue.')
    step.value = steps.value[1]
    return
  }
  if (step.value === 'account') {
    if (password.value.length < 8) return fail('Use a password with at least 8 characters.')
    busy.value = true
    try {
      const { needsVerification } = await auth.signUp(fullName.value.trim(), email.value.trim(), password.value, 'workspace', planKey.value)
      if (needsVerification) { verifySent.value = true; return }
      step.value = 'organisation'
    } catch (e) { fail(friendlyError(e)) } finally { busy.value = false }
    return
  }
  if (step.value === 'organisation') {
    if (orgName.value.trim().length < 2) return fail('Enter your organisation name.')
    if (website.value.trim() && !/^https?:\/\/\S+$/i.test(website.value.trim())) return fail('Website must start with http:// or https://')
    if (!workspaceName.value) workspaceName.value = orgName.value.trim()
    if (!contactEmail.value) contactEmail.value = auth.user?.email ?? ''
    step.value = 'workspace'
  }
}
function back() {
  error.value = ''
  const i = stepIndex.value
  if (i > 0) step.value = steps.value[i - 1]
}

function onLogo(e: Event) {
  error.value = ''
  const file = (e.target as HTMLInputElement).files?.[0] ?? null
  if (file) {
    const problem = validateLogo(file)
    if (problem) { error.value = problem; logoFile.value = null; return }
  }
  logoFile.value = file
}

async function create() {
  error.value = ''
  if (slug.value.length < 3) return fail('The workspace address needs at least 3 characters.')
  busy.value = true
  try {
    const { data, error: err } = await supabase.rpc('create_workspace', {
      p_name: orgName.value.trim(),
      p_workspace_name: workspaceName.value.trim(),
      p_slug: slug.value,
      p_org_type: orgType.value,
      p_plan_key: planKey.value,
      p_description: description.value.trim() || null,
      p_country: country.value.trim() || null,
      p_contact_email: contactEmail.value.trim() || null,
      p_contact_phone: contactPhone.value.trim() || null,
      p_website: website.value.trim() || null,
    })
    if (err) throw err
    const orgId = data as string

    // Logo is optional and must never block workspace creation.
    let logoFailed = false
    if (logoFile.value) {
      try {
        const url = await uploadOrgLogo(orgId, logoFile.value)
        const { error: upErr } = await supabase.from('organisations').update({ logo_url: url }).eq('id', orgId)
        if (upErr) throw upErr
      } catch { logoFailed = true }
    }

    // One welcome email per workspace (the function deduplicates). It must never block or fail setup.
    supabase.functions.invoke('send-email', { body: { template: 'workspace_welcome', org_id: orgId } }).catch(() => { /* email is optional */ })

    await ws.load()
    await ws.switchTo(orgId)
    router.replace({ name: 'dashboard', query: logoFailed ? { logo: 'failed' } : {} })
  } catch (e) { fail(friendlyError(e)) } finally { busy.value = false }
}

// ---- load ----
onMounted(async () => {
  await auth.init()
  if (signedIn.value && !ws.loaded) { try { await ws.load() } catch { /* handled by hub */ } }
  // One independent workspace per customer: if they already own one, go there.
  if (ws.ownedWorkspace) { router.replace({ name: 'dashboard' }); return }

  const { data } = await supabase.from('plans')
    .select('key, name, description, price_month_minor, currency, trial_days, plan_entitlements(key, value)')
    .order('price_month_minor')
  plans.value = (data as PlanRow[] | null) ?? []
  plansLoaded.value = true

  const fromQuery = typeof route.query.plan === 'string' ? route.query.plan : null
  const fromMeta = (auth.user?.user_metadata?.intended_plan as string | undefined) ?? null
  const wanted = fromQuery ?? fromMeta
  if (wanted && plans.value.some(p => p.key === wanted)) planKey.value = wanted
  // Someone who verified their email and came back already chose a plan and has an account.
  if (signedIn.value && fromMeta && plans.value.some(p => p.key === fromMeta)) step.value = 'organisation'
  if (signedIn.value) fullName.value = auth.profile?.full_name ?? ''
})
</script>

<template>
  <div class="mx-auto max-w-3xl px-4 py-12 sm:py-16">
    <!-- Verification holding screen -->
    <template v-if="verifySent">
      <h1 class="text-3xl font-bold">Check your email</h1>
      <p class="mt-3 max-w-prose text-muted">
        We sent a confirmation link to <strong class="text-ink">{{ email }}</strong>. After you confirm, you will come back here to finish
        setting up your organisation. Your plan choice is saved.
      </p>
      <RouterLink to="/login" class="link mt-6 inline-block">Go to sign in</RouterLink>
    </template>

    <template v-else>
      <p class="text-sm font-semibold text-violet">Create Your Own LMS</p>
      <h1 class="mt-1 text-3xl font-bold">Set up your learning platform</h1>
      <p class="mt-2 max-w-prose text-muted">
        You are creating an independent workspace for your own students. It is separate from the official Tech Village learning platform.
      </p>

      <ol class="mt-8 flex flex-wrap gap-x-6 gap-y-2 text-sm" aria-label="Progress">
        <li v-for="(s, i) in steps" :key="s" :aria-current="s === step ? 'step' : undefined"
            :class="s === step ? 'font-semibold text-brand' : i < stepIndex ? 'text-ink' : 'text-muted'">
          {{ i + 1 }}. {{ stepLabels[s] }}
        </li>
      </ol>

      <div class="mt-6"><SetupNotice /></div>

      <!-- STEP: plan -->
      <form v-if="step === 'plan'" class="mt-6 space-y-6" @submit.prevent="next">
        <fieldset>
          <legend class="mb-3 font-display text-lg font-semibold">Choose a plan</legend>
          <p v-if="plansLoaded && !plans.length" class="text-sm text-muted">Plans could not be loaded. Check your connection and refresh.</p>
          <div class="grid gap-3 sm:grid-cols-3">
            <label v-for="p in plans" :key="p.key"
                   class="cursor-pointer rounded-panel border p-4 has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-brand"
                   :class="planKey === p.key ? 'border-brand bg-brand-soft' : 'border-line hover:border-muted'">
              <input v-model="planKey" type="radio" name="plan" :value="p.key" class="sr-only" />
              <span class="block font-semibold">{{ p.name }}</span>
              <span class="mt-0.5 block text-sm font-medium text-brand">{{ price(p) }}</span>
              <span class="mt-2 block text-sm text-muted">{{ p.description }}</span>
              <ul class="mt-3 space-y-1 text-sm">
                <li v-for="h in highlights(p)" :key="h">{{ h }}</li>
              </ul>
              <span v-if="p.trial_days" class="mt-3 block text-xs font-medium text-mint-text">{{ p.trial_days }}-day free trial</span>
            </label>
          </div>
          <p class="mt-3 text-sm text-muted">Payments are not connected yet. Paid plans start as a free trial and you will not be charged.</p>
        </fieldset>
        <p v-if="error" role="alert" class="rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
        <div class="flex items-center gap-4">
          <BaseButton type="submit" size="lg" :disabled="!plans.length">Continue</BaseButton>
          <RouterLink v-if="!signedIn" :to="{ name: 'login', query: { next: '/signup/lms' } }" class="link text-sm">I already have an account</RouterLink>
        </div>
      </form>

      <!-- STEP: account (only when not signed in) -->
      <form v-else-if="step === 'account'" class="panel mt-6 space-y-5 p-6" @submit.prevent="next">
        <h2 class="font-display text-lg font-semibold">Your personal account</h2>
        <p class="text-sm text-muted">This is you, the person. Your organisation comes next.</p>
        <BaseField v-model="fullName" label="Full name" autocomplete="name" required />
        <BaseField v-model="email" label="Email" type="email" autocomplete="email" required />
        <BaseField v-model="password" label="Password" type="password" autocomplete="new-password" hint="At least 8 characters." required :minlength="8" />
        <p v-if="error" role="alert" class="rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
        <div class="flex gap-3">
          <BaseButton variant="secondary" @click="back">Back</BaseButton>
          <BaseButton type="submit" :loading="busy" :disabled="!isSupabaseConfigured">Create account and continue</BaseButton>
        </div>
      </form>

      <!-- STEP: organisation -->
      <form v-else-if="step === 'organisation'" class="panel mt-6 space-y-5 p-6" @submit.prevent="next">
        <h2 class="font-display text-lg font-semibold">Your organisation</h2>
        <BaseField v-model="orgName" label="Organisation name" required :minlength="2" />
        <BaseSelect v-model="orgType" label="Organisation type" :options="orgTypeOptions" required />
        <BaseTextarea v-model="description" label="Description" :maxlength="1000" hint="Optional. A sentence or two about what you teach." />
        <div class="grid gap-5 sm:grid-cols-2">
          <BaseField v-model="country" label="Country" autocomplete="country-name" />
          <BaseField v-model="website" label="Website" type="url" placeholder="https://" hint="Optional." />
          <BaseField v-model="contactEmail" label="Contact email" type="email" autocomplete="email" />
          <BaseField v-model="contactPhone" label="Contact phone" type="tel" autocomplete="tel" hint="Optional." />
        </div>
        <p v-if="error" role="alert" class="rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
        <div class="flex gap-3">
          <BaseButton variant="secondary" @click="back">Back</BaseButton>
          <BaseButton type="submit">Continue</BaseButton>
        </div>
      </form>

      <!-- STEP: workspace -->
      <form v-else class="panel mt-6 space-y-5 p-6" @submit.prevent="create">
        <h2 class="font-display text-lg font-semibold">Your workspace</h2>
        <BaseField v-model="workspaceName" label="Workspace name" required :minlength="2" hint="What your students will see, for example “Osahon’s Academy”." />
        <BaseField v-model="slug" label="Workspace address" required :minlength="3" hint="Lowercase letters, numbers and hyphens. It must be unique and cannot be changed later."
                   @update:model-value="slugTouched = true" />
        <div>
          <label for="logo" class="block text-sm font-medium">Logo <span class="font-normal text-muted">(optional)</span></label>
          <div class="mt-1.5 flex items-center gap-4">
            <img v-if="logoPreview" :src="logoPreview" alt="Logo preview" class="h-14 w-14 rounded-md border border-line object-cover" />
            <input id="logo" type="file" accept="image/png,image/jpeg,image/webp" class="text-sm file:mr-3 file:rounded-control file:border-0 file:bg-brand-soft file:px-4 file:py-2 file:font-semibold file:text-brand" @change="onLogo" />
          </div>
          <p class="mt-1.5 text-sm text-muted">PNG, JPEG or WebP, up to 2 MB. You can add or change it later.</p>
        </div>

        <dl class="rounded-control bg-sunken p-4 text-sm">
          <div class="flex justify-between gap-4"><dt class="text-muted">Organisation</dt><dd class="font-medium">{{ orgName }}</dd></div>
          <div class="mt-1 flex justify-between gap-4"><dt class="text-muted">Type</dt><dd class="font-medium">{{ ORG_TYPE_LABELS[orgType] }}</dd></div>
          <div class="mt-1 flex justify-between gap-4"><dt class="text-muted">Plan</dt><dd class="font-medium">{{ selectedPlan?.name }}</dd></div>
        </dl>

        <p v-if="error" role="alert" class="rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
        <div class="flex gap-3">
          <BaseButton variant="secondary" @click="back">Back</BaseButton>
          <BaseButton type="submit" size="lg" :loading="busy">Create my workspace</BaseButton>
        </div>
        <p class="text-sm text-muted">You will become the owner and administrator of this workspace.</p>
      </form>
    </template>
  </div>
</template>
