<script setup lang="ts">
import { computed } from 'vue'
import type { DayStats } from '../composables/stats'
import type { GuardStats } from '../composables/guard'
import { guardName } from '../composables/guard'
import { fmtKB, shortPkg, type MemRow } from '../composables/memview'

const props = defineProps<{
  stats: DayStats | null
  engineUp: boolean | null
  capsOk: number
  white: { pkg: string; adj: number | null; states: string[] }[]
  guard: GuardStats | null
  memtop: MemRow[]
  frozen: { count: number; pkgs: string[] } | null
  memLoading: boolean
  freeing: boolean
}>()
const emit = defineEmits<{ refreshMem: []; release: [] }>()

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
const memMax = computed(() => Math.max(1, ...(props.memtop.map(r => r.kb) ?? [1])))
const memPct = (kb: number) => `${Math.max(6, (kb / memMax.value) * 100)}%`
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

  <!-- 内存占用 + 系统墓碑 (v1.1.0 面板增强包) -->
  <div class="card mf-grid">
    <div class="mf-col">
      <div class="mf-head">
        <b>内存占用 TOP</b>
        <button class="mf-btn" :disabled="memLoading" @click="emit('refreshMem')">
          {{ memLoading ? '读取中…' : '刷新' }}
        </button>
      </div>
      <div v-if="!memtop.length" class="mf-empty">{{ memLoading ? 'dumpsys 统计中（约 3 秒）…' : '点刷新读取' }}</div>
      <div v-for="(r, i) in memtop" :key="r.pkg" class="mf-row">
        <span class="mf-i">{{ i + 1 }}</span>
        <span class="mf-pkg">{{ shortPkg(r.pkg) }}</span>
        <span class="mf-bar"><i :style="{ width: memPct(r.kb) }" /></span>
        <span class="mf-kb">{{ fmtKB(r.kb) }}</span>
      </div>
    </div>
    <div class="mf-col">
      <div class="mf-head"><b>系统墓碑</b><span class="mf-sub">ColorOS 冻结覆盖</span></div>
      <div class="mf-fz"><b>{{ frozen?.count ?? '—' }}</b><i>个进程冻结待机</i></div>
      <div class="mf-pills">
        <span v-for="p in (frozen?.pkgs ?? []).slice(0, 8)" :key="p" class="pill">{{ shortPkg(p) }}</span>
        <span v-if="(frozen?.pkgs.length ?? 0) > 8" class="pill">+{{ (frozen?.pkgs.length ?? 0) - 8 }}</span>
      </div>
      <button class="mf-release" :disabled="freeing || !frozen" @click="emit('release')">
        {{ freeing ? '已触发…' : '立即释放缓存' }}
      </button>
      <div class="mf-note">按当前档位清理非白名单缓存 · 白名单免疫</div>
    </div>
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
.mf-grid{display:grid; grid-template-columns:1fr 1fr; gap:14px}
.mf-col{min-width:0}
.mf-head{display:flex; align-items:center; justify-content:space-between; gap:6px; margin-bottom:8px}
.mf-head b{font-size:13px}
.mf-sub{font-size:10px; color:var(--ink3)}
.mf-btn{font-size:11px; padding:3px 10px; border-radius:8px; border:1px solid var(--sep);
  background:transparent; color:var(--ink2); cursor:pointer}
.mf-btn:disabled{opacity:.5}
.mf-empty{font-size:11px; color:var(--ink3); padding:14px 0; text-align:center}
.mf-row{display:grid; grid-template-columns:14px minmax(48px,auto) 1fr auto; gap:6px;
  align-items:center; font-size:11px; padding:3px 0}
.mf-i{color:var(--ink3); font-size:10px}
.mf-pkg{color:var(--ink); font-weight:500; overflow:hidden; text-overflow:ellipsis; white-space:nowrap}
.mf-bar{height:6px; background:var(--sep); border-radius:3px; overflow:hidden}
.mf-bar i{display:block; height:100%; background:var(--green); border-radius:3px}
.mf-kb{color:var(--ink2); font-variant-numeric:tabular-nums}
.mf-fz{display:flex; align-items:baseline; gap:6px; margin:6px 0 8px}
.mf-fz b{font-size:30px; font-weight:700; color:var(--green)}
.mf-fz i{font-size:11px; color:var(--ink2); font-style:normal}
.mf-pills{display:flex; flex-wrap:wrap; gap:5px; margin-bottom:12px; max-height:66px; overflow:hidden}
.mf-pills .pill{font-size:10px; padding:2px 8px; border-radius:999px; background:var(--green-bg);
  color:var(--ink2); border:1px solid var(--sep)}
.mf-release{width:100%; padding:10px; border-radius:12px; border:0; font-size:13px; font-weight:600;
  background:var(--green); color:#fff; cursor:pointer}
.mf-release:disabled{opacity:.55}
.mf-note{font-size:10px; color:var(--ink3); text-align:center; margin-top:6px}
@media (max-width:420px){.mf-grid{grid-template-columns:1fr}}
</style>
