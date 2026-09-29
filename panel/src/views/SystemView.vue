<script setup lang="ts">
import type { DayStats } from '../composables/stats'
import { CAP_LABELS } from '../composables/stats'

defineProps<{ stats: DayStats | null; capsEntries: [string, number][] }>()

const MODE: Record<string, string> = {
  CAP_LRU: '进程快照', CAP_LRU_FALLBACK: '备用快照源', CAP_PSI: '内存压力',
  CAP_ADJ: 'adj 写入', CAP_LMKD_CFG: 'lmkd 调参', CAP_OPLUS: 'Oplus 扩展',
}
const CAP_ICON: Record<string, string> = {
  CAP_LRU: 'i-apps-2-fill', CAP_LRU_FALLBACK: 'i-stack-fill', CAP_PSI: 'i-dashboard-2-fill',
  CAP_ADJ: 'i-tools-fill', CAP_LMKD_CFG: 'i-cpu-fill', CAP_OPLUS: 'i-smartphone-fill',
}
</script>

<template>
  <!-- 能力探测 -->
  <div class="sec"><div class="b"><svg class="si" viewBox="0 0 24 24"><use href="#i-puzzle-fill"/></svg></div><h2>能力探测</h2></div>
  <div class="grid">
    <div v-for="[k, v] in capsEntries" :key="k" class="tile">
      <div class="th"><span class="pill" :class="v === 1 ? 'ok' : 'bad'">{{ v === 1 ? '支持' : '不支持' }}</span></div>
      <div class="ic"><svg class="si" viewBox="0 0 24 24"><use :href="'#' + (CAP_ICON[k] ?? 'i-information-fill')"/></svg></div>
      <div class="t">{{ MODE[k] ?? CAP_LABELS[k] ?? k }}</div>
    </div>
    <div v-if="!capsEntries.length" class="tile">
      <div class="ic">…</div><div class="t">等待引擎</div><div class="s">caps.conf 未生成</div>
    </div>
  </div>

  <!-- 异常监控 -->
  <div class="sec"><div class="b"><svg class="si" viewBox="0 0 24 24"><use href="#i-information-fill"/></svg></div><h2>异常监控</h2></div>
  <div class="card">
    <div class="row"><div class="name">哨兵停机</div>
      <span class="pill" :class="(stats?.sentinelHalt ?? 0) > 0 ? 'bad' : 'ok'">{{ stats?.sentinelHalt ?? 0 }}</span></div>
    <div class="row"><div class="name">看门狗重启</div>
      <span class="pill" :class="(stats?.watchdogRestarts ?? 0) > 0 ? 'warn' : 'ok'">{{ stats?.watchdogRestarts ?? 0 }}</span></div>
    <div class="row"><div class="name">名单非法行</div>
      <span class="pill" :class="(stats?.listBad ?? 0) > 0 ? 'warn' : 'ok'">{{ stats?.listBad ?? 0 }}</span></div>
    <div class="row"><div class="name">白名单拦截<small style="color:var(--ink2)">（点名杀被拦）</small></div>
      <span class="pill" :class="(stats?.skipped ?? 0) > 0 ? 'ok' : ''">{{ stats?.skipped ?? 0 }}</span></div>
    <div class="row"><div class="name">白名单死亡<small style="color:var(--ink2)">（进程消失事件）</small></div>
      <span class="pill" :class="(stats?.deaths ?? 0) > 0 ? 'warn' : 'ok'">{{ stats?.deaths ?? 0 }}</span></div>
  </div>
</template>
