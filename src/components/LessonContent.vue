<script setup lang="ts">
import { computed } from 'vue'
import { embedUrl } from '@/lib/video'
import type { BlockRow } from '@/lib/courses'

const props = defineProps<{ blocks: BlockRow[] }>()

// Text is rendered as text, never as HTML, so an author cannot inject markup or scripts.
// Blank lines separate paragraphs.
const rendered = computed(() => props.blocks.map(b => ({
  id: b.id,
  type: b.block_type,
  paragraphs: b.block_type === 'text' ? (b.body ?? '').split(/\n{2,}/).map(p => p.trim()).filter(Boolean) : [],
  embed: b.block_type === 'video' && b.video_url ? embedUrl(b.video_url) : null,
})))
</script>

<template>
  <div class="space-y-6">
    <p v-if="!blocks.length" class="rounded-control bg-sunken px-4 py-3 text-sm text-muted">This lesson has no content yet.</p>
    <template v-for="b in rendered" :key="b.id">
      <div v-if="b.type === 'text'" class="max-w-prose space-y-4 leading-relaxed">
        <p v-for="(p, i) in b.paragraphs" :key="i" class="whitespace-pre-line">{{ p }}</p>
      </div>
      <div v-else-if="b.embed" class="aspect-video w-full overflow-hidden rounded-panel border border-line bg-sunken">
        <iframe :src="b.embed" title="Lesson video" class="h-full w-full" loading="lazy" referrerpolicy="strict-origin-when-cross-origin"
                sandbox="allow-scripts allow-same-origin allow-presentation" allow="fullscreen; picture-in-picture" allowfullscreen />
      </div>
      <p v-else class="rounded-control bg-warn-soft px-4 py-3 text-sm text-warn">This video link is not supported and cannot be shown.</p>
    </template>
  </div>
</template>
