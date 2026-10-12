<script setup lang="ts">
import { useId } from 'vue'
defineProps<{ label: string; modelValue: string; hint?: string; maxlength?: number; rows?: number; placeholder?: string }>()
defineEmits<{ 'update:modelValue': [value: string] }>()
const id = useId()
</script>

<template>
  <div class="space-y-1.5">
    <label :for="id" class="block text-sm font-medium text-ink">{{ label }}</label>
    <textarea :id="id" :value="modelValue" :maxlength="maxlength" :rows="rows ?? 3" :placeholder="placeholder"
              class="w-full rounded-control border border-line bg-raised px-3.5 py-2.5 text-ink placeholder:text-muted/70 hover:border-muted focus:border-brand"
              @input="$emit('update:modelValue', ($event.target as HTMLTextAreaElement).value)" />
    <p v-if="hint" class="text-sm text-muted">{{ hint }}</p>
  </div>
</template>
