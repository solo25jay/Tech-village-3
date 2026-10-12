<script setup lang="ts">
import { useId } from 'vue'
withDefaults(defineProps<{
  label: string
  modelValue: string
  type?: string
  hint?: string
  error?: string
  autocomplete?: string
  required?: boolean
  placeholder?: string
  minlength?: number
  disabled?: boolean
}>(), { type: 'text' })
defineEmits<{ 'update:modelValue': [value: string] }>()
const id = useId()
</script>

<template>
  <div class="space-y-1.5">
    <label :for="id" class="block text-sm font-medium text-ink">{{ label }}</label>
    <input
      :id="id" :type="type" :value="modelValue" :autocomplete="autocomplete" :required="required"
      :placeholder="placeholder" :minlength="minlength" :disabled="disabled"
      :aria-invalid="!!error" :aria-describedby="error || hint ? id + '-d' : undefined"
      class="h-11 w-full rounded-control border bg-raised px-3.5 text-ink placeholder:text-muted/70 disabled:bg-sunken disabled:text-muted"
      :class="error ? 'border-danger' : 'border-line hover:border-muted focus:border-brand'"
      @input="$emit('update:modelValue', ($event.target as HTMLInputElement).value)"
    />
    <p v-if="error || hint" :id="id + '-d'" class="text-sm" :class="error ? 'text-danger' : 'text-muted'">{{ error || hint }}</p>
  </div>
</template>
