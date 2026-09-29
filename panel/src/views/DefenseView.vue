<script setup lang="ts">
import GuardPanel from '../components/GuardPanel.vue'
import type { GuardStats } from '../composables/guard'

defineProps<{ guard: GuardStats | null }>()
const emit = defineEmits<{ (e: 'pick', date: string): void }>()
</script>

<template>
  <GuardPanel :stats="guard" @pick="(d) => emit('pick', d)" />
</template>
