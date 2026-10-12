<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import BaseButton from '@/components/BaseButton.vue'
import { supabase } from '@/lib/supabase'
import { friendlyError } from '@/lib/errors'
import { useWorkspaceStore } from '@/stores/workspace'

const ws = useWorkspaceStore()
const router = useRouter()
const busy = ref(false)
const error = ref('')

async function join() {
  busy.value = true; error.value = ''
  try {
    const { error: err } = await supabase.rpc('join_tech_village')
    if (err) throw err
    await ws.load()
    router.replace({ name: 'learn-dashboard' })
  } catch (e) { error.value = friendlyError(e) } finally { busy.value = false }
}
</script>

<template>
  <div class="max-w-xl">
    <h1 class="text-3xl font-bold">Join the Tech Village learning platform</h1>
    <p class="mt-3 text-muted">
      You are signed in but have not joined the official Tech Village LMS yet. Joining adds you as a learner. It does not change any workspace you manage.
    </p>
    <p v-if="error" role="alert" class="mt-4 rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
    <BaseButton class="mt-6" size="lg" :loading="busy" @click="join">Join Tech Village</BaseButton>
  </div>
</template>
