<script setup lang="ts">
import GuardPanel from '../components/GuardPanel.vue'
import type { GuardStats } from '../composables/guard'

defineProps<{ guard: GuardStats | null; listRaw: string; mod: string }>()
const emit = defineEmits<{ (e: 'pick', date: string): void; (e: 'edited'): void }>()
</script>

<template>
  <GuardPanel :stats="guard" :listRaw="listRaw" :mod="mod"
    @pick="(d) => emit('pick', d)" @edited="emit('edited')" />
</template>
