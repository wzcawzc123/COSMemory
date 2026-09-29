<script setup lang="ts">
import { computed } from 'vue'
import type { DayStats } from '../composables/stats'
import type { GuardStats } from '../composables/guard'
import { guardName } from '../composables/guard'

const props = defineProps<{
  stats: DayStats | null
  engineUp: boolean | null
  capsOk: number
  white: { pkg: string; adj: number | null; states: string[] }[]
  guard: GuardStats | null
}>()

const lights = computed(() => [
  { label: '引擎', on: props.engineUp === true, icon: 'i-cpu-fill' },
  { label: '防线', on: props.guard?.module === 'installed', icon: 'i-lock-unlock-fill' },
  { label: '名单', on: props.white.length > 0, icon: 'i-user-smile-fill' },
  { label: '快照', on: !!props.guard && props.guard.snapshot_age_s >= 0
      && props.guard.snapshot_age_s < 3600, icon: 'i-refresh-fill' },
])
const aliveCount = computed(() => props.white.filter(w => w.states.length > 0).length)
const ring = (pct: number) => `${Math.min(100, Math.max(0, pct)) * 1.2566} 125.66`
const capsPct = computed(() => (props.capsOk / 6) * 100)
const alivePct = computed(() => (aliveCount.value / Math.max(1, props.white.length)) * 100)
const sparkMax = computed(() => Math.max(1, ...(props.guard?.hourly.map(h => h.block + h.fuse) ?? [1])))
</script>

<template>
  <!-- 状态灯行 -->
  <div class="card d-lights">
    <div v-for="l in lights" :key="l.label" class="d-light">
      <span class="d-dot" :class="{ on: l.on }" />
      <svg class="si" viewBox="0 0 24 24"><use :href="'#' + l.icon" /></svg>
      <i>{{ l.label }}</i>
    </div>
  </div>

  <!-- 核心四数 -->
  <div class="hero">
    <div class="hp"><div class="n">{{ stats?.keepAdj ?? '—' }}</div><div class="l">今日保活</div></div>
    <div class="hp"><div class="n">{{ stats?.killed ?? '—' }}</div><div class="l">今日回收</div></div>
    <div class="hp"><div class="n">{{ guard?.today.block ?? '—' }}</div><div class="l">防线拦截</div></div>
    <div class="hp"><div class="n">{{ (guard?.today.error ?? 0) + (stats?.sentinelHalt ?? 0) }}</div><div class="l">异常</div></div>
  </div>

  <!-- 双 gauge + 迷你趋势 -->
  <div class="card d-mid">
    <div class="d-gauge">
      <svg viewBox="0 0 52 52">
        <circle cx="26" cy="26" r="20" fill="none" stroke="var(--sep)" stroke-width="6" />
        <circle cx="26" cy="26" r="20" fill="none" stroke="var(--green)" stroke-width="6"
          stroke-linecap="round" :stroke-dasharray="ring(capsPct)" stroke-dashoffset="0"
          transform="rotate(-90 26 26)" />
        <text x="26" y="29" text-anchor="middle" class="d-num">{{ capsOk }}/6</text>
      </svg>
      <i>能力探测</i>
    </div>
    <div class="d-gauge">
      <svg viewBox="0 0 52 52">
        <circle cx="26" cy="26" r="20" fill="none" stroke="var(--sep)" stroke-width="6" />
        <circle cx="26" cy="26" r="20" fill="none" stroke="var(--amber)" stroke-width="6"
          stroke-linecap="round" :stroke-dasharray="ring(alivePct)" stroke-dashoffset="0"
          transform="rotate(-90 26 26)" />
        <text x="26" y="29" text-anchor="middle" class="d-num">{{ aliveCount }}/{{ white.length }}</text>
      </svg>
      <i>名单存活</i>
    </div>
    <div class="d-spark">
      <b>24h 拦截</b>
      <svg viewBox="0 0 192 40" preserveAspectRatio="none">
        <g v-for="h in (guard?.hourly ?? [])" :key="h.h">
          <rect :x="h.h * 8 + 1" :width="6" :y="40 - (h.block / sparkMax) * 36"
                :height="(h.block / sparkMax) * 36" fill="#e8863a" rx="1" />
          <rect :x="h.h * 8 + 1" :width="6" :y="40 - ((h.block + h.fuse) / sparkMax) * 36"
                :height="(h.fuse / sparkMax) * 36" fill="#e5484d" rx="1" />
        </g>
      </svg>
      <span v-if="!guard || (!guard.today.block && !guard.today.fuse)" class="d-spark-e">今日无拦截</span>
    </div>
  </div>

  <!-- 白名单健康卡 -->
  <div class="gd-grid">
    <div v-for="w in white" :key="w.pkg" class="card gd-app">
      <div class="gd-app-top">
        <b>{{ guardName(w.pkg) }}</b>
        <span class="pill" :class="w.states.length ? 'ok' : 'bad'">
          {{ w.states.length ? '存活' : '离线' }}</span>
      </div>
      <div class="gd-app-n"><b>{{ w.cchAdj === null ? '—' : w.cchAdj }}</b><i>cchAdj</i></div>
      <div class="gd-app-t">{{ w.states.join(' · ') || '不在快照' }}</div>
    </div>
    <div v-if="!white.length" class="card gd-empty">名单未加载</div>
  </div>
</template>

<style scoped>
.d-lights{display:grid; grid-template-columns:repeat(4,1fr); gap:6px; padding:12px 8px}
.d-light{display:flex; flex-direction:column; align-items:center; gap:4px; font-size:11px; color:var(--ink2)}
.d-light .si{width:18px; height:18px; fill:var(--ink3)}
.d-dot{width:8px; height:8px; border-radius:50%; background:var(--ink3)}
.d-dot.on{background:var(--green); box-shadow:0 0 0 3px var(--green-bg)}
.d-mid{display:flex; align-items:center; gap:14px; flex-wrap:wrap}
.d-gauge{display:flex; flex-direction:column; align-items:center; gap:3px; font-size:11px; color:var(--ink2)}
.d-gauge svg{width:64px; height:64px}
.d-num{font-size:11px; fill:var(--ink); font-weight:600}
.d-spark{flex:1; min-width:130px; position:relative}
.d-spark b{font-size:12px; font-weight:600}
.d-spark svg{width:100%; height:40px; display:block; margin-top:4px}
.d-spark-e{position:absolute; inset:0; display:flex; align-items:center; justify-content:center;
  font-size:11px; color:var(--ink2)}
</style>
