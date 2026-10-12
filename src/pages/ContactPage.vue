<script setup lang="ts">
import { ref, computed } from 'vue'
import { useRoute } from 'vue-router'
import BaseField from '@/components/BaseField.vue'
import BaseButton from '@/components/BaseButton.vue'
import { isSupabaseConfigured } from '@/lib/supabase'
import { sendContactMessage, ContactError } from '@/services/email'

const route = useRoute()
const topics = [
  { value: 'general', label: 'General question' },
  { value: 'programme', label: 'Programme interest' },
  { value: 'saas', label: 'Running my own platform' },
  { value: 'partnership', label: 'Partnership' },
]
const q = (k: string) => (typeof route.query[k] === 'string' ? (route.query[k] as string) : '')

const name = ref('')
const email = ref('')
const topic = ref(topics.some(t => t.value === q('topic')) ? q('topic') : 'general')
const subject = ref(q('about') ? `Interested in: ${q('about').slice(0, 100)}` : '')
const message = ref('')
const website = ref('') // honeypot
const busy = ref(false)
const done = ref(false)
const error = ref('')
const fieldErrors = ref<Record<string, string>>({})
const messageId = 'contact-message'
const charsLeft = computed(() => 5000 - message.value.length)

async function submit() {
  error.value = ''; fieldErrors.value = {}; busy.value = true
  try {
    await sendContactMessage({ name: name.value, email: email.value, topic: topic.value, subject: subject.value, message: message.value, website: website.value })
    done.value = true
  } catch (e) {
    if (e instanceof ContactError) { error.value = e.message; fieldErrors.value = e.fields ?? {} }
    else error.value = 'We could not send your message. Please try again in a moment.'
  } finally { busy.value = false }
}
</script>

<template>
  <section class="mx-auto grid max-w-6xl gap-12 px-4 py-14 sm:px-6 sm:py-20 lg:grid-cols-[1fr_1.2fr]">
    <div>
      <h1 class="text-4xl font-extrabold sm:text-5xl">Talk to us</h1>
      <p class="mt-5 max-w-prose text-lg text-muted">
        Questions about a programme, running your own learning platform, or working together? Send a message and a member of the team will reply by email.
      </p>
    </div>

    <div>
      <div v-if="done" class="panel p-8" role="status">
        <h2 class="text-2xl font-bold">Message sent</h2>
        <p class="mt-3 text-muted">Thank you. We have sent a confirmation to <strong class="text-ink">{{ email }}</strong> and will reply there.</p>
      </div>

      <form v-else class="panel space-y-5 p-6" novalidate @submit.prevent="submit">
        <p v-if="!isSupabaseConfigured" class="rounded-control border border-warn/40 bg-warn-soft px-3 py-2 text-sm text-warn" role="status">
          Contact is not connected yet. Connect Supabase and deploy the contact function to enable this form.
        </p>
        <BaseField v-model="name" label="Your name" autocomplete="name" required :error="fieldErrors.name" />
        <BaseField v-model="email" label="Email" type="email" autocomplete="email" required :error="fieldErrors.email" />
        <div class="space-y-1.5">
          <label for="contact-topic" class="block text-sm font-medium">What is this about?</label>
          <select id="contact-topic" v-model="topic" class="h-11 w-full rounded-control border border-line bg-raised px-3 text-ink hover:border-muted focus:border-brand">
            <option v-for="t in topics" :key="t.value" :value="t.value">{{ t.label }}</option>
          </select>
        </div>
        <BaseField v-model="subject" label="Subject (optional)" :error="fieldErrors.subject" />
        <div class="space-y-1.5">
          <label :for="messageId" class="block text-sm font-medium">Message</label>
          <textarea :id="messageId" v-model="message" rows="6" maxlength="5000" required
                    class="w-full rounded-control border bg-raised px-3.5 py-3 text-ink"
                    :class="fieldErrors.message ? 'border-danger' : 'border-line hover:border-muted focus:border-brand'"
                    :aria-invalid="!!fieldErrors.message" :aria-describedby="messageId + '-d'" />
          <p :id="messageId + '-d'" class="text-sm" :class="fieldErrors.message ? 'text-danger' : 'text-muted'">
            {{ fieldErrors.message || `${charsLeft.toLocaleString('en')} characters left` }}
          </p>
        </div>
        <!-- Honeypot: hidden from people and assistive tech, bots tend to fill it in. -->
        <div class="absolute -left-[9999px]" aria-hidden="true">
          <label>Leave this field empty<input v-model="website" type="text" tabindex="-1" autocomplete="off" /></label>
        </div>
        <p v-if="error" role="alert" class="rounded-control bg-danger-soft px-3 py-2 text-sm text-danger">{{ error }}</p>
        <BaseButton type="submit" size="lg" :loading="busy" :disabled="!isSupabaseConfigured">Send message</BaseButton>
      </form>
    </div>
  </section>
</template>
