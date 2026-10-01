<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { detectBridge, execRead, type KsuBridge } from './composables/ksu'
import { parseStats, parseCaps, whiteStatus, CAP_LABELS, type DayStats } from './composables/stats'
import { parseGuard, guardDate, type GuardStats } from './composables/guard'
import { initTheme } from './composables/theme'
import DashboardView from './views/DashboardView.vue'
import DefenseView from './views/DefenseView.vue'
import SystemView from './views/SystemView.vue'
import ListView from './views/ListView.vue'
import SettingsView from './views/SettingsView.vue'

const MOD = '/data/adb/modules/COSMemory'
const LIST = '/sdcard/Android/COSMemory/名单列表.conf'

const bridge = ref<KsuBridge | null>(detectBridge())
const stats = ref<DayStats | null>(null)
const caps = ref<Record<string, number>>({})
const white = ref<{ pkg: string; adj: number | null; states: string[] }[]>([])
const logTail = ref<string[]>([])
const engineUp = ref<boolean | null>(null)
const error = ref('')
const guard = ref<GuardStats | null>(null)
const listRaw = ref('')
type Tab = 'dash' | 'defense' | 'system' | 'list' | 'set'
const activeTab = ref<Tab>('dash')
function goTab(id: Tab) { activeTab.value = id; window.scrollTo({ top: 0 }) }
let timer: number | undefined

const MODE: Record<string, string> = {
  CAP_LRU: '进程快照', CAP_LRU_FALLBACK: '备用快照源', CAP_PSI: '内存压力',
  CAP_ADJ: 'adj 写入', CAP_LMKD_CFG: 'lmkd 调参', CAP_OPLUS: 'Oplus 扩展',
}

// 能力 → Solar sprite 图标(与显示增强模块同款组件包)
const CAP_ICON: Record<string, string> = {
  CAP_LRU: 'i-apps-2-fill', CAP_LRU_FALLBACK: 'i-stack-fill', CAP_PSI: 'i-dashboard-2-fill',
  CAP_ADJ: 'i-tools-fill', CAP_LMKD_CFG: 'i-cpu-fill', CAP_OPLUS: 'i-smartphone-fill',
}

async function refresh() {
  const b = bridge.value
  if (!b) { error.value = '未检测到 KSU 桥（请在 KernelSU 管理器中打开）'; return }
  try {
    // 阶段1: 全部小文件 + pgrep (总耗时 ≤25ms; 不再遍历 /proc)
    const [log, capsTxt, listTxt, parsed, livePid, guardTxt] = await Promise.all([
      execRead(b, `tail -100 ${MOD}/data/stats.log 2>/dev/null`),
      execRead(b, `cat ${MOD}/data/caps.conf 2>/dev/null`),
      execRead(b, `cat "${LIST}" 2>/dev/null`),
      execRead(b, `cat ${MOD}/data/parsed.txt 2>/dev/null`),
      execRead(b, 'pgrep -f engine/memory.sh 2>/dev/null || true'),
      execRead(b, `sh ${MOD}/engine/guard_stats.sh ${guardDate.value || ''}`).catch(() => ''),
    ])
    stats.value = parseStats(log)
    guard.value = parseGuard(guardTxt)
    caps.value = parseCaps(capsTxt)
    const wl = listTxt.split('\n').filter(l => l.startsWith('WHITE ')).map(l => l.slice(6).trim()).join(' ')
    listRaw.value = listTxt

    // 解析引擎快照 → pid 信息表 (state|proc|pid|pkg)
    const pidInfo = new Map<string, { state: string; pkg: string }>()
    const stateMap = new Map<string, string>()
    for (const l of parsed.split('\n')) {
      const [st, , pid, pkg] = l.split('|')
      if (!pkg || !pid) continue
      stateMap.set(pkg, st)
      pidInfo.set(pid, { state: st, pkg })
    }

    // 阶段2: 只读白名单命中的 pid 的实时 adj (5~10个, ~15ms)
    const wlArr = wl.split(/\s+/).filter(Boolean)
    const wantPids = [...pidInfo.entries()]
      .filter(([, v]) => wlArr.some(w => v.pkg === w || (!w.includes(':') && v.pkg.startsWith(w + ':'))))
      .map(([pid]) => pid)
    let adjOut = ''
    if (wantPids.length) {
      adjOut = await execRead(b,
        `for p in ${wantPids.join(' ')}; do echo "$p $(cat /proc/$p/oom_score_adj 2>/dev/null)"; done`)
    }

    // 拼成 whiteStatus 需要的 state|adj|pkg 行
    const rows: string[] = []
    for (const line of adjOut.split('\n')) {
      const [pid, adj] = line.trim().split(/\s+/)
      const info = pidInfo.get(pid)
      if (info && adj) rows.push(`${info.state}|${adj}|${info.pkg}`)
    }
    white.value = whiteStatus(rows.join('\n'), wl)
    logTail.value = log.split('\n').filter(Boolean).slice(-50).reverse()
    engineUp.value = livePid.trim().length > 0
    error.value = ''
  } catch (e) { error.value = String(e) }
}

const TABS: { id: Tab; label: string; icon: string }[] = [
  { id: 'dash', label: '总览', icon: 'i-dashboard-2-fill' },
  { id: 'defense', label: '防线', icon: 'i-lock-unlock-fill' },
  { id: 'system', label: '系统', icon: 'i-cpu-fill' },
  { id: 'list', label: '名单', icon: 'i-user-smile-fill' },
  { id: 'set', label: '设置', icon: 'i-tools-fill' },
]

const capsOk = computed(() => Object.values(caps.value).filter(v => v === 1).length)
const capsEntries = computed(() => Object.entries(caps.value))

/** 设置页模式开关: 写 memory.json mode → 30s 桥自动生效(热加载) */
async function setGuardMode(toGuard: boolean) {
  const b = bridge.value
  if (!b) { error.value = '无 KSU 桥'; return }
  const target = toGuard ? 'guard' : 'observe'
  try {
    await execRead(b, `sed -i 's/"mode": *"[a-z]*"/"mode": "${target}"/' ${MOD}/config/memory.json`)
    const back = await execRead(b, `grep -o '"mode": "[a-z]*"' ${MOD}/config/memory.json`)
    if (back.includes(target)) {
      if (guard.value) guard.value = { ...guard.value, mode: target }
      error.value = ''
      alert(`已切换为 ${target}，30 秒内经配置桥生效`)
    } else error.value = '模式切换失败: ' + (back.trim() || '空回读')
  } catch (e) { error.value = String(e) }
}

/** 设置页激进回收: sed节内定向写(引擎每轮热读≤8s), 回读验证(防空回读教训) */
async function setReclaim(patch: { aggressive?: boolean; depth?: string }) {
  const b = bridge.value
  if (!b) { error.value = '无 KSU 桥'; return }
  try {
    if (patch.aggressive !== undefined) {
      const to = patch.aggressive ? 'true' : 'false'
      const from = patch.aggressive ? 'false' : 'true'
      await execRead(b, `sed -i '/"reclaim"/,/}/s/"aggressive": ${from}/"aggressive": ${to}/' ${MOD}/config/memory.json`)
    }
    if (patch.depth !== undefined) {
      await execRead(b, `sed -i '/"reclaim"/,/}/s/"depth": "[a-z]*"/"depth": "${patch.depth}"/' ${MOD}/config/memory.json`)
    }
    const back = await execRead(b, `sed -n '/"reclaim"/,/}/p' ${MOD}/config/memory.json`)
    const ok = patch.depth !== undefined
      ? back.includes(`"depth": "${patch.depth}"`)
      : back.includes(`"aggressive": ${patch.aggressive ? 'true' : 'false'}`)
    if (ok) {
      error.value = ''
      if (guard.value) guard.value = { ...guard.value,
        reclaimAggressive: back.includes('"aggressive": true'),
        reclaimDepth: (back.match(/"depth": "([a-z]*)"/) ?? [])[1] ?? 'cached' }
    } else error.value = '激进回收写入失败: 回读不符'
  } catch (e) { error.value = String(e) }
}

onMounted(() => { initTheme(); refresh(); timer = window.setInterval(refresh, 5000) })
onUnmounted(() => { if (timer) clearInterval(timer) })

</script>

<template>
  <div class="hd">
    <div>
      <h1>COSMemory</h1>
      <div class="sub">
        <template v-if="engineUp === null">连接中…</template>
        <template v-else-if="engineUp">内存管理 · 引擎运行中</template>
        <template v-else>内存管理 · 引擎未运行</template>
      </div>
    </div>
    <div class="dot" :class="engineUp ? 'on' : 'off'" />
  </div>

  <div class="wrap">
    <div v-if="error" class="alert" :class="{ ok: error.includes('已切换') }">{{ error }}</div>

    <DashboardView v-if="activeTab === 'dash'"
      :stats="stats" :engine-up="engineUp" :caps-ok="capsOk" :white="white" :guard="guard" />
    <DefenseView v-else-if="activeTab === 'defense'"
      :guard="guard" @pick="(d) => { guardDate.value = d; refresh(); }" />
    <SystemView v-else-if="activeTab === 'system'"
      :stats="stats" :caps-entries="capsEntries" />
    <ListView v-else-if="activeTab === 'list'"
      :white="white" :list-raw="listRaw"
      :freezeList="guard?.freezeList ?? []"
      :mod="MOD" @edited="refresh" />
    <SettingsView v-else
      :log-tail="logTail" :guard="guard" @set-guard-mode="setGuardMode" @set-reclaim="setReclaim" />
  </div>

  <!-- 底部导航 5 键 -->
  <nav class="tabbar">
    <button v-for="t in TABS" :key="t.id" :class="{ on: activeTab === t.id }"
      @click="goTab(t.id)">
      <svg class="si" viewBox="0 0 24 24"><use :href="'#' + t.icon" /></svg>
      <span>{{ t.label }}</span>
    </button>
  </nav>
</template>
