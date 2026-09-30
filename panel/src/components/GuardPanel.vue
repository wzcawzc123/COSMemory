<script setup lang="ts">
import { computed, ref } from 'vue'
import type { GuardStats } from '../composables/guard'
import { guardName, guardDate } from '../composables/guard'

const props = defineProps<{ stats: GuardStats | null }>()
const emit = defineEmits<{ (e: 'pick', date: string): void }>()
const dateOpen = ref(false)
function pickDate(d: string) { dateOpen.value = false; if (d !== guardDate.value) emit('pick', d) }

const RULE_LABEL: Record<string, string> = {
  'o-stop': 'Oplus强停', frozen: '冻结同步异常', cached: '缓存超限',
  empty: '空进程超限', cpu: 'CPU超限',
}
const stale = computed(() =>
  props.stats != null && props.stats.snapshot_age_s > 3600)
const moduleOk = computed(() => props.stats?.module === 'installed')
const hMax = computed(() => Math.max(1,
  ...(props.stats?.hourly.map(x => x.block + x.fuse) ?? [1])))
const ruleMax = computed(() => Math.max(1, ...(props.stats?.rules.map(r => r.n) ?? [1])))
const fmtTs = (s: number) =>
  s > 0 ? new Date(s * 1000).toLocaleString('zh-CN', { hour12: false }).slice(5) : '—'
const fmtHour = (h: number) => String(h).padStart(2, '0') + ':00'
</script>

<template>
  <div class="gd-wrap" v-if="stats">
    <!-- W1 状态总览 -->
    <div class="gd-hero card">
      <div class="gd-pills">
        <span class="pill" :class="stats.mode === 'guard' ? 'bad' : 'ok'">
          {{ stats.mode === 'guard' ? '拦截中' : '观察模式' }}</span>
        <span class="pill" :class="moduleOk ? 'ok' : ''">
          {{ moduleOk ? '模块已装' : '模块未装' }}</span>
        <span class="pill" :class="stale ? 'warn' : (stats.live_today ? 'ok' : '')">
          名单 {{ stats.snapshot_age_s < 0 ? '缺失'
                 : (stale ? '滞后' + Math.round(stats.snapshot_age_s / 60) + '分' : '新鲜') }}</span>
      </div>
      <div class="gd-nums">
        <div class="gd-num"><b>{{ stats.today.block }}</b><i>今日拦截</i></div>
        <div class="gd-num"><b>{{ stats.today.fuse }}</b><i>保险丝触发</i></div>
        <div class="gd-num"><b>{{ stats.today.error }}</b><i>异常</i></div>
        <div class="gd-num"><b>{{ stats.today.pass_observe }}</b><i>观察记录</i></div>
        <div class="gd-num"><b>{{ stats.freezeToday }}</b><i>今日封杀</i></div>
      </div>
    </div>

    <!-- W2 24h 趋势 (纯 SVG) -->
    <div class="card">
      <div class="gd-row"><b>24 小时拦截趋势</b>
        <span class="gd-legend"><i class="gd-b"></i>拦截 <i class="gd-f"></i>保险丝</span></div>
      <svg class="gd-bars" :viewBox="`0 0 ${24*16} 64`" preserveAspectRatio="none">
        <g v-for="x in stats.hourly" :key="x.h">
          <rect :x="x.h*16+1" :width="14" :y="64 - (x.block/hMax)*60"
                :height="(x.block/hMax)*60" fill="var(--ok, #e8863a)" rx="1"/>
          <rect :x="x.h*16+1" :width="14"
                :y="64 - (x.block+x.fuse)/hMax*60"
                :height="(x.fuse/hMax)*60" fill="#e5484d" rx="1">
            <title>{{ fmtHour(x.h) }} 拦截{{ x.block }} 保险丝{{ x.fuse }}</title>
          </rect>
        </g>
      </svg>
      <div class="gd-axis"><span>00时</span><span>12时</span><span>23时</span></div>
    </div>
    <!-- W3 规则命中分布 -->
    <div class="card">
      <b>威胁规则分布</b>
      <div v-if="!stats.rules.length" class="gd-empty">今日无命中</div>
      <div v-for="r in stats.rules" :key="r.rule" class="gd-rule">
        <span class="gd-rl">{{ RULE_LABEL[r.rule] ?? r.rule }}</span>
        <span class="gd-rbar"><i :style="{ width: (r.n / ruleMax * 100) + '%' }"/></span>
        <span class="gd-rn">{{ r.n }}</span>
      </div>
    </div>

    <!-- W4 白名单应用卡片 -->
    <div class="gd-grid">
      <div v-for="w in stats.whitelist" :key="w.pkg" class="card gd-app">
        <div class="gd-app-top">
          <b>{{ guardName(w.pkg) }}</b>
          <span class="pill" :class="w.last_act === 'BLOCK' ? 'ok' : ''">
            {{ w.last_act === 'BLOCK' ? '已保活' : (w.last_act || '无事件') }}</span>
        </div>
        <div class="gd-app-n"><b>{{ w.block }}</b><i>今日拦截</i></div>
        <div class="gd-app-t">最近 {{ fmtTs(w.last_ts) }}</div>
      </div>
      <div v-if="!stats.whitelist.length" class="card gd-empty">名单内应用今日无事件</div>
    </div>

    <!-- W5 最近事件流 + 日期切换 -->
    <div class="card">
      <div class="gd-row"><b>最近事件</b>
        <div class="gd-sel-wrap">
          <button type="button" class="gd-sel" @click.stop="dateOpen = !dateOpen">{{ guardDate || '今天' }}<i class="gd-caret">▾</i></button>
          <div v-if="dateOpen" class="gd-mask" @click="dateOpen = false" />
          <div v-if="dateOpen" class="gd-menu">
            <button type="button" :class="{ on: !guardDate }" @click="pickDate('')">今天</button>
            <button v-for="ds in stats.dates" :key="ds" type="button" :class="{ on: guardDate === ds }" @click="pickDate(ds)">{{ ds }}</button>
          </div>
        </div>
      </div>
      <div v-if="!stats.recent.length" class="gd-empty">暂无事件</div>
      <div v-for="(r, i) in stats.recent" :key="i" class="gd-ev">
        <span class="gd-ev-t">{{ fmtTs(r.ts) }}</span>
        <span class="gd-ev-p">{{ guardName(r.pkg) }}</span>
        <span class="gd-ev-r">{{ (RULE_LABEL[r.rule] ?? r.rule) || '—' }}</span>
        <span class="pill" :class="r.act === 'BLOCK' ? 'ok'
          : r.act === 'FUSE' || r.act === 'ERROR' ? 'bad' : ''">{{ r.act }}</span>
        <div class="gd-ev-reason">{{ r.reason }}</div>
      </div>
    </div>
  </div>
  <div v-else class="card gd-empty">AMS防线 数据未就绪（检查模块安装与 KSU 桥）</div>
</template>
<style scoped>
.gd-wrap{display:flex;flex-direction:column;gap:10px}
.gd-hero{display:flex;flex-direction:column;gap:10px}
.gd-pills{display:flex;gap:6px;flex-wrap:wrap}
.gd-nums{display:grid;grid-template-columns:repeat(5,1fr);gap:8px}
.gd-num{text-align:center}.gd-num b{font-size:22px;display:block}
.gd-num i{font-style:normal;font-size:11px;color:var(--ink2,#888)}
.gd-bars{width:100%;height:64px;display:block}
.gd-axis{display:flex;justify-content:space-between;font-size:10px;color:var(--ink2,#888)}
.gd-legend{font-size:11px;color:var(--ink2,#888);display:flex;gap:8px;align-items:center}
.gd-legend i{width:9px;height:9px;display:inline-block;border-radius:2px}
.gd-b{background:#e8863a}.gd-f{background:#e5484d}
.gd-rule{display:grid;grid-template-columns:72px 1fr 32px;gap:8px;align-items:center;margin-top:6px}
.gd-rbar{background:rgba(128,128,128,.18);height:10px;border-radius:5px;overflow:hidden}
.gd-rbar i{display:block;height:100%;background:#e8863a}
.gd-rn{text-align:right;font-size:12px}
.gd-ev{display:grid;grid-template-columns:auto 1fr auto auto;gap:8px;align-items:center;
  padding:6px 0;border-top:1px solid rgba(128,128,128,.15);font-size:12px}
.gd-ev-t{color:var(--ink2,#888)}
.gd-ev-reason{grid-column:1/-1;color:var(--ink2,#888);font-size:11px;word-break:break-all}
.gd-sel-wrap{position:relative}
.gd-sel{font-size:12px;padding:4px 8px;border-radius:8px;background:transparent;
  border:1px solid rgba(128,128,128,.35);color:inherit;display:flex;align-items:center;gap:6px}
.gd-caret{font-style:normal;font-size:10px;opacity:.7}
.gd-mask{position:fixed;inset:0;z-index:39;background:transparent}
.gd-menu{position:absolute;right:0;top:calc(100% + 6px);min-width:150px;max-height:240px;
  overflow:auto;background:var(--card2);border:1px solid var(--sep);border-radius:12px;
  box-shadow:0 8px 24px rgba(0,0,0,.35);z-index:40;padding:4px;
  display:flex;flex-direction:column}
.gd-menu button{font-size:13px;padding:9px 12px;border:none;border-radius:8px;
  background:transparent;color:var(--ink);text-align:left}
.gd-menu button.on{background:var(--green-bg);color:var(--green);font-weight:700}
.gd-row{display:flex;justify-content:space-between;align-items:center}
</style>
