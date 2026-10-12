<script setup lang="ts">
import { useId } from 'vue'
defineProps<{
  label: string
  modelValue: string
  options: { value: string; label: string }[]
  hint?: string
  required?: boolean
}>()
defineEmits<{ 'update:modelValue': [value: string] }>()
const id = useId()
</script>

<template>
  <div class="space-y-1.5">
    <label :for="id" class="block text-sm font-medium text-ink">{{ label }}</label>
    <select :id="id" :value="modelValue" :required="required"
            class="h-11 w-full rounded-control border border-line bg-raised px-3 text-ink hover:border-muted focus:border-brand"
            @change="$emit('update:modelValue', ($event.target as HTMLSelectElement).value)">
      <option v-for="o in options" :key="o.value" :value="o.value">{{ o.label }}</option>
    </select>
    <p v-if="hint" class="text-sm text-muted">{{ hint }}</p>
  </div>
</template>
