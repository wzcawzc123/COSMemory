<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { themeMode, setTheme, type ThemeMode } from '../composables/theme'
import { detectBridge, execRead } from '../composables/ksu'
import type { GuardStats } from '../composables/guard'

const props = defineProps<{ logTail: string[]; guard: GuardStats | null }>()
const emit = defineEmits<{ (e: 'set-guard-mode', v: boolean): void }>()

// ---- 外观 ----
const THEMES: { v: ThemeMode; label: string }[] = [
  { v: 'light', label: '浅色' }, { v: 'dark', label: '深色' }, { v: 'system', label: '跟随系统' },
]

// ---- 模式开关 ----
const mode = ref(props.guard?.mode ?? 'observe')
const pending = ref(false)          // 确认态
function toggleMode() {
  if (props.guard?.mode !== 'observe' && props.guard?.mode !== 'guard') return
  if (!pending.value) { pending.value = true; return }   // 第一次点=进入确认
  pending.value = false
  emit('set-guard-mode', mode.value === 'observe')       // 目标=切换后
}
function cancelConfirm() { pending.value = false }

// ---- 日志折叠 ----
const logOpen = ref(false)

// ---- 设备信息 ----
const dev = ref('读取中…')
onMounted(async () => {
  const b = detectBridge()
  if (!b) { dev.value = '无 KSU 桥'; return }
  dev.value = (await execRead(b,
    'getprop ro.product.model; getprop ro.build.display.id; uname -r'
  )).trim().split('\n').filter(Boolean).join(' · ') || '—'
})
</script>

<template>
  <!-- 外观 -->
  <div class="sec"><div class="b"><svg class="si" viewBox="0 0 24 24"><use href="#i-sun-fill"/></svg></div><h2>外观</h2></div>
  <div class="card st-seg">
    <button v-for="t in THEMES" :key="t.v" class="st-seg-b"
      :class="{ on: themeMode === t.v }" @click="setTheme(t.v)">{{ t.label }}</button>
  </div>

  <!-- 防线模式 -->
  <div class="sec"><div class="b"><svg class="si" viewBox="0 0 24 24"><use href="#i-lock-unlock-fill"/></svg></div><h2>防线模式</h2></div>
  <div class="card st-mode">
    <div class="st-mode-row">
      <div>
        <div class="name">{{ mode === 'guard' ? '拦截模式' : '观察模式' }}</div>
        <div class="meta">
          {{ mode === 'guard' ? '白名单被系统强停等杀因时拦截保活' : '只记录不拦截 (observe)' }}
        </div>
      </div>
      <button class="st-switch" :class="{ on: mode === 'guard' }" @click="toggleMode">
        <i /><span v-if="pending" class="st-confirm">确认?</span>
      </button>
    </div>
    <div v-if="pending" class="st-hint">
      切换后 30s 内经配置桥生效（无需重启）。{{ mode === 'guard' ? '将开始真实拦截。' : '回到只记录。' }}
      <button class="st-cancel" @click="cancelConfirm">取消</button>
    </div>
  </div>

  <!-- 引擎日志(折叠) -->
  <div class="sec"><div class="b"><svg class="si" viewBox="0 0 24 24"><use href="#i-terminal-box-fill"/></svg></div><h2>引擎日志</h2></div>
  <div class="card st-log">
    <button class="st-log-t" @click="logOpen = !logOpen">
      <span>{{ logOpen ? '收起' : '展开最近 50 行' }}</span>
      <span class="st-log-n">{{ logTail.length }} 行</span>
    </button>
    <div v-if="logOpen" class="logbox">
      <div v-if="!logTail.length" class="empty">暂无日志</div>
      <div v-for="(l, i) in logTail" :key="i" class="logline"
        :class="{ bad: /SENTINEL|WATCHDOG|halt/.test(l) }">{{ l }}</div>
    </div>
  </div>

  <!-- 设备信息 -->
  <div class="sec"><div class="b"><svg class="si" viewBox="0 0 24 24"><use href="#i-smartphone-fill"/></svg></div><h2>设备信息</h2></div>
  <div class="card st-dev">{{ dev }}</div>

  <!-- 关于 -->
  <div class="sec"><div class="b"><svg class="si" viewBox="0 0 24 24"><use href="#i-award-fill"/></svg></div><h2>关于</h2></div>
  <div class="card st-about">
    <div class="st-about-t">COSMemory <b>v0.4.0</b></div>
    <div class="st-about-s">白名单保活 + 智能回收 · 阶段二「AMS防线」</div>
    <div class="st-about-line">作者：<b>是你吗薰儿</b></div>
    <div class="st-about-line">
      基于 <a href="https://github.com/OneB1ank/A1Memory" target="_blank" rel="noreferrer">
      HChai / OneB1ank 的 A1Memory</a> 二次开发（GPLv3）
    </div>
    <div class="st-about-s st-about-path">
      数据：/data/adb/modules/COSMemory/data/ · 防线桥：/data/system/cosmem/
    </div>
  </div>
</template>

<style scoped>
.st-seg{display:grid; grid-template-columns:repeat(3,1fr); gap:6px; padding:8px}
.st-seg-b{border:none; background:transparent; color:var(--ink2); font-size:13px;
  padding:9px 0; border-radius:var(--radius-s); cursor:pointer}
.st-seg-b.on{background:var(--card2); color:var(--ink); font-weight:600}
.st-mode-row{display:flex; align-items:center; justify-content:space-between; gap:10px}
.st-switch{position:relative; min-width:64px; height:32px; border-radius:100px; border:none;
  background:var(--pill-line); cursor:pointer; display:flex; align-items:center;
  justify-content:center; gap:6px}
.st-switch i{position:absolute; left:4px; top:4px; width:24px; height:24px; border-radius:50%;
  background:var(--ink3); transition:transform .18s}
.st-switch.on{background:var(--green-bg)}
.st-switch.on i{transform:translateX(32px); background:var(--green)}
.st-confirm{font-size:11px; color:var(--red); font-weight:700; z-index:1; padding-left:14px}
.st-hint{margin-top:8px; font-size:12px; color:var(--ink2); display:flex; gap:8px;
  align-items:center; flex-wrap:wrap}
.st-cancel{border:1px solid var(--sep); background:transparent; color:var(--ink2);
  font-size:12px; padding:3px 10px; border-radius:8px; cursor:pointer}
.st-log-t{width:100%; display:flex; justify-content:space-between; border:none;
  background:transparent; color:var(--ink); font-size:13px; padding:4px 0; cursor:pointer}
.st-log-n{color:var(--ink2)}
.st-log .logbox{margin-top:8px; max-height:300px; overflow:auto}
.st-dev{font-family:ui-monospace,Menlo,monospace; font-size:12px; color:var(--ink2);
  word-break:break-all}
.st-about-t{font-size:15px}
.st-about-s{font-size:12px; color:var(--ink2); margin-top:3px}
.st-about-line{font-size:13px; margin-top:7px}
.st-about-line a{color:var(--green)}
.st-about-path{margin-top:10px; font-family:ui-monospace,Menlo,monospace; font-size:11px}
</style>
