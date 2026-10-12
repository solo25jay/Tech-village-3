<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import BaseButton from '@/components/BaseButton.vue'
import { supabase, isSupabaseConfigured } from '@/lib/supabase'
import { formatEntitlements, annualSavingPercent, formatMoney, type EntitlementRow } from '@/lib/entitlements'

interface PlanRow {
  key: string; name: string; description: string | null
  price_month_minor: number; price_year_minor: number; currency: string; trial_days: number
  plan_entitlements: EntitlementRow[]
}

const plans = ref<PlanRow[]>([])
const loading = ref(true)
const failed = ref(false)
const yearly = ref(false)

onMounted(async () => {
  if (!isSupabaseConfigured) { loading.value = false; return }
  const { data, error } = await supabase.from('plans')
    .select('key, name, description, price_month_minor, price_year_minor, currency, trial_days, plan_entitlements(key, value)')
    .order('price_month_minor')
  if (error) failed.value = true
  plans.value = (data as unknown as PlanRow[] | null) ?? []
  loading.value = false
})

const saving = computed(() => Math.max(0, ...plans.value.map(p => annualSavingPercent(p.price_month_minor, p.price_year_minor))))
const view = computed(() => plans.value.map(p => ({
  ...p,
  features: formatEntitlements(p.plan_entitlements),
  price: formatMoney(yearly.value ? p.price_year_minor : p.price_month_minor, p.currency),
  free: p.price_month_minor <= 0,
})))
</script>

<template>
  <section class="mx-auto max-w-6xl px-4 py-14 sm:px-6 sm:py-20">
    <h1 class="max-w-3xl text-4xl font-extrabold sm:text-5xl">Plans for every kind of teacher</h1>
    <p class="mt-5 max-w-prose text-lg text-muted">
      Start with one course and a handful of students, and grow as your organisation does.
      Every plan includes private, separate data for your students and courses.
    </p>

    <div v-if="plans.length && saving > 0" class="mt-8 inline-flex rounded-control border border-line bg-raised p-1" role="group" aria-label="Billing period">
      <button type="button" class="rounded-md px-4 py-2 text-sm font-semibold" :class="!yearly ? 'bg-brand text-brand-on' : 'text-muted hover:text-ink'" :aria-pressed="!yearly" @click="yearly = false">Monthly</button>
      <button type="button" class="rounded-md px-4 py-2 text-sm font-semibold" :class="yearly ? 'bg-brand text-brand-on' : 'text-muted hover:text-ink'" :aria-pressed="yearly" @click="yearly = true">
        Yearly <span class="ml-1 text-xs opacity-90">save up to {{ saving }}%</span>
      </button>
    </div>

    <p v-if="loading" class="mt-10 text-muted" role="status">Loading plans...</p>
    <p v-else-if="!isSupabaseConfigured" class="mt-10 rounded-control border border-warn/40 bg-warn-soft p-4 text-sm text-warn" role="status">
      Plans are read from your Supabase project. Connect Supabase to see them here.
    </p>
    <p v-else-if="failed || !plans.length" class="mt-10 text-muted" role="alert">Plans could not be loaded right now. Please refresh, or <RouterLink to="/contact" class="link">contact us</RouterLink>.</p>

    <ul v-else class="mt-10 grid gap-5 lg:grid-cols-3">
      <li v-for="p in view" :key="p.key" class="panel flex flex-col p-6">
        <h2 class="text-xl font-bold">{{ p.name }}</h2>
        <p class="mt-1 min-h-[2.75rem] text-sm text-muted">{{ p.description }}</p>
        <p class="mt-5 flex items-baseline gap-1.5">
          <span class="font-display text-4xl font-extrabold">{{ p.price }}</span>
          <span v-if="!p.free" class="text-sm text-muted">per {{ yearly ? 'year' : 'month' }}</span>
        </p>
        <p v-if="p.trial_days" class="mt-1 text-sm font-medium text-mint-text">{{ p.trial_days }}-day free trial</p>
        <ul class="mt-6 flex-1 space-y-2.5 text-sm">
          <li v-for="f in p.features" :key="f.key" class="flex items-start gap-2.5" :class="!f.included && 'text-muted'">
            <svg v-if="f.included" class="mt-0.5 h-4 w-4 shrink-0 text-mint-text" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2.2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="m4 10.5 4 4 8-9" /></svg>
            <svg v-else class="mt-0.5 h-4 w-4 shrink-0" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" d="M5 10h10" /></svg>
            <span><span class="sr-only">{{ f.included ? 'Included: ' : 'Not included: ' }}</span>{{ f.label }}</span>
          </li>
        </ul>
        <div class="mt-8"><BaseButton :to="{ name: 'signup-lms', query: { plan: p.key } }" class="w-full">{{ p.free ? 'Start free' : p.trial_days ? 'Start free trial' : 'Get started' }}</BaseButton></div>
      </li>
    </ul>
    <p class="mt-6 max-w-prose text-sm text-muted">Online payment is being connected. Paid plans currently begin as a free trial and you are not charged.</p>
  </section>
</template>
