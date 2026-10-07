<script setup lang="ts">
import { ref, onMounted, watch } from 'vue'
import { themeMode, setTheme, type ThemeMode } from '../composables/theme'
import { detectBridge, execRead } from '../composables/ksu'
import type { GuardStats } from '../composables/guard'

const props = defineProps<{ logTail: string[]; guard: GuardStats | null; diagBusy: boolean }>()
const emit = defineEmits<{ (e: 'set-guard-mode', v: boolean): void; (e: 'set-reclaim', p: { aggressive?: boolean; depth?: string }): void; (e: 'export-diag'): void; (e: 'set-uro-bridge', v: boolean): void }>()

// ---- URO 统一调度桥接开关（UnifiedRootOptimizer enforce）----
// 开关文件由本面板写、URO 每个策略边界热读；文件缺省/0 = 关（只 dry-run）
const URO_CONF = '/sdcard/Android/UnifiedRootOptimizer/uro.conf'
const uroOn = ref(false)
const pendingU = ref(false)
function toggleUro() {
  if (!pendingU.value) { pendingU.value = true; return }
  pendingU.value = false
  emit('set-uro-bridge', !uroOn.value)
}
function cancelUro() { pendingU.value = false }

// ---- 外观 ----
const THEMES: { v: ThemeMode; label: string }[] = [
  { v: 'light', label: '浅色' }, { v: 'dark', label: '深色' }, { v: 'system', label: '跟随系统' },
]

// ---- 模式开关 ----
const mode = ref(props.guard?.mode ?? 'observe')
const pending = ref(false)          // 确认态
const pendingR = ref(false)
const raOn = ref(false)
const raDepth = ref('cached')
// v0.7.2: 引擎术语 → 直白档位 (温和=cached只清缓存 / 标准=+prev刚切走 / 彻底=+svc空服务)
const DEPTH_LABEL: Record<string, [string, string]> = {
  cached: ['温和', '只清闲置最久的缓存进程'],
  previous: ['标准', '刚切到后台的也会清'],
  service: ['彻底', '连空服务进程一起清'],
}
watch(() => props.guard?.reclaimAggressive, v => { if (v !== undefined) raOn.value = v }, { immediate: true })
watch(() => props.guard?.reclaimDepth, v => { if (v) raDepth.value = v }, { immediate: true })
function toggleReclaim() {
  if (!pendingR.value) { pendingR.value = true; return }
  pendingR.value = false
  emit('set-reclaim', { aggressive: !raOn.value })
}
function pickDepth(d: string) { raDepth.value = d; emit('set-reclaim', { depth: d }) }
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
// 动态版本号: 单一源头 = module.prop 的 version 行 (发版只改 module.prop, 关于页自动跟随)
const ver = ref('…')
onMounted(async () => {
  const b = detectBridge()
  if (!b) { dev.value = '无 KSU 桥'; ver.value = '?'; return }
  const [v, d, u] = await Promise.all([
    execRead(b, 'grep "^version=" /data/adb/modules/COSMemory/module.prop'),
    execRead(b, 'getprop ro.product.model; getprop ro.build.display.id; uname -r'),
    execRead(b, `grep '^BRIDGE_ENFORCE=' ${URO_CONF} 2>/dev/null`),
  ])
  ver.value = v.split('=')[1]?.trim() || '?'
  dev.value = d.trim().split('\n').filter(Boolean).join(' · ') || '—'
  uroOn.value = /BRIDGE_ENFORCE=1/.test(u)
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

  <!-- 激进回收 -->
  <div class="sec"><div class="b"><svg class="si" viewBox="0 0 24 24"><use href="#i-cpu-fill"/></svg></div><h2>激进回收</h2></div>
  <div class="card st-mode">
    <div class="st-mode-row">
      <div>
        <div class="name">{{ raOn ? '激进回收开 · ' + (DEPTH_LABEL[raDepth]?.[0] ?? raDepth) : '激进回收关' }}</div>
        <div class="meta">内存压力时按档清理非白名单(白名单免疫), ≤8 秒热生效</div>
      </div>
      <button class="st-switch" :class="{ on: raOn }" @click="toggleReclaim">
        <i /><span v-if="pendingR" class="st-confirm">确认?</span>
      </button>
    </div>
    <div class="st-mode-row" v-if="raOn" style="margin-top:10px; flex-wrap: wrap">
      <div class="meta" style="width:100%">回收深度</div>
      <div class="st-seg" style="width:100%">
        <button v-for="d in [['cached','温和'],['previous','标准'],['service','彻底']]" :key="d[0]"
          class="st-seg-b" :class="{ on: raDepth === d[0] }" @click="pickDepth(d[0])">{{ d[1] }}</button>
      </div>
      <div class="meta" style="width:100%; margin-top:6px">{{ DEPTH_LABEL[raDepth]?.[1] }}</div>
    </div>
  </div>

  <!-- 统一调度桥接 (UnifiedRootOptimizer) -->
  <div class="sec"><div class="b"><svg class="si" viewBox="0 0 24 24"><use href="#i-cpu-fill"/></svg></div><h2>统一调度桥接</h2></div>
  <div class="card st-mode">
    <div class="st-mode-row">
      <div>
        <div class="name">{{ uroOn ? 'URO 场景接管 · 开' : 'URO 场景接管 · 关' }}</div>
        <div class="meta">
          {{ uroOn
            ? '由 UnifiedRootOptimizer 按场景自动调本页回收策略：游戏时自动暂停让权、内存压力/省电时自动开启；此时手改回收开关会在下个场景被覆盖'
            : '关闭时回收策略完全由本页手动控制（推荐保持关闭，除非已安装 URO）' }}
        </div>
      </div>
      <button class="st-switch" :class="{ on: uroOn }" @click="toggleUro">
        <i /><span v-if="pendingU" class="st-confirm">确认?</span>
      </button>
    </div>
    <div v-if="pendingU" class="st-hint">
      {{ uroOn ? '关闭后 URO 不再写入本页回收策略（下次策略事件生效）。' : '开启后 URO 将按场景自动写入本配置，可随时关闭。' }}
      <button class="st-cancel" @click="cancelUro">取消</button>
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

  <!-- 诊断与反馈 -->
  <div class="sec"><div class="b"><svg class="si" viewBox="0 0 24 24"><use href="#i-file-cloud-fill"/></svg></div><h2>诊断与反馈</h2></div>
  <div class="card st-diag">
    <div class="st-about-s">导出引擎/防线/设备诊断日志为单个文本文件，保存到 /sdcard/Download/（文件名含时间戳），反馈问题时附带即可定位（只含模块日志与机型属性，不含个人数据；logcat 仅截取 COSGuard/COSMemory 相关行）。</div>
    <button class="st-diag-btn" :disabled="diagBusy" @click="emit('export-diag')">
      {{ diagBusy ? '导出中…' : '导出诊断日志' }}
    </button>
  </div>

  <!-- 设备信息 -->
  <div class="sec"><div class="b"><svg class="si" viewBox="0 0 24 24"><use href="#i-smartphone-fill"/></svg></div><h2>设备信息</h2></div>
  <div class="card st-dev">{{ dev }}</div>

  <!-- 关于 -->
  <div class="sec"><div class="b"><svg class="si" viewBox="0 0 24 24"><use href="#i-award-fill"/></svg></div><h2>关于</h2></div>
  <div class="card st-about">
    <div class="st-about-t">COSMemory <b>v{{ ver }}</b></div>
    <div class="st-about-s">白名单保活 + 智能回收 + AMS 防线</div>
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
.st-diag{display:flex; flex-direction:column; gap:10px}
.st-diag-btn{width:100%; padding:10px; border-radius:12px; border:0; font-size:13px; font-weight:600;
  background:var(--green); color:#fff; cursor:pointer}
.st-diag-btn:disabled{opacity:.55}
</style>
