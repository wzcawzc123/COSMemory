<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { detectBridge, execRead, type KsuBridge } from './composables/ksu'
import { parseStats, parseCaps, whiteStatus, CAP_LABELS, type DayStats } from './composables/stats'

const MOD = '/data/adb/modules/COSMemory'
const LIST = '/sdcard/Android/COSMemory/名单列表.conf'

const bridge = ref<KsuBridge | null>(detectBridge())
const stats = ref<DayStats | null>(null)
const caps = ref<Record<string, number>>({})
const white = ref<{ pkg: string; adj: number | null; states: string[] }[]>([])
const logTail = ref<string[]>([])
const engineUp = ref<boolean | null>(null)
const error = ref('')
let timer: number | undefined

const MODE: Record<string, string> = {
  CAP_LRU: '进程快照', CAP_LRU_FALLBACK: '备用快照源', CAP_PSI: '内存压力',
  CAP_ADJ: 'adj 写入', CAP_LMKD_CFG: 'lmkd 调参', CAP_OPLUS: 'Oplus 扩展',
}

async function refresh() {
  const b = bridge.value
  if (!b) { error.value = '未检测到 KSU 桥（请在 KernelSU 管理器中打开）'; return }
  try {
    const [log, capsTxt, listTxt, parsed, procs] = await Promise.all([
      execRead(b, `tail -100 ${MOD}/data/stats.log 2>/dev/null`),
      execRead(b, `cat ${MOD}/data/caps.conf 2>/dev/null`),
      execRead(b, `cat "${LIST}" 2>/dev/null`),
      execRead(b, `cat ${MOD}/data/parsed.txt 2>/dev/null`),
      execRead(b, `for d in /proc/[0-9]*; do c=$(tr '\\0' ' ' < $d/cmdline 2>/dev/null); case "$c" in *tencent.mm*|*tencent.mobileqq*|*ugc.aweme*) echo "$(cat $d/oom_score_adj 2>/dev/null)|$c";; esac; done`),
    ])
    stats.value = parseStats(log)
    caps.value = parseCaps(capsTxt)
    const wl = listTxt.split('\n').filter(l => l.startsWith('WHITE ')).map(l => l.slice(6).trim()).join(' ')
    const stateMap = new Map<string, string>()
    for (const l of parsed.split('\n')) {
      const [st, , , pkg] = l.split('|'); if (pkg) stateMap.set(pkg, st)
    }
    const rows = procs.split('\n').filter(Boolean).map(l => {
      const i = l.indexOf('|')
      const adj = l.slice(0, i), cmd = l.slice(i + 1).trim()
      const pkg = cmd.split(/\s+/)[0]
      return `${stateMap.get(pkg) ?? ''}|${adj}|${pkg}`
    })
    white.value = whiteStatus(rows.join('\n'), wl)
    logTail.value = log.split('\n').filter(Boolean).slice(-50).reverse()
    engineUp.value = stats.value.engineStarted
    error.value = ''
  } catch (e) { error.value = String(e) }
}

const capsOk = computed(() => Object.values(caps.value).filter(v => v === 1).length)
const capsEntries = computed(() => Object.entries(caps.value))

onMounted(() => { refresh(); timer = window.setInterval(refresh, 5000) })
onUnmounted(() => { if (timer) clearInterval(timer) })
</script>

<template>
  <div class="nav">
    <h1>COSMemory</h1>
    <div class="sub">
      <template v-if="engineUp === null">加载中…</template>
      <template v-else-if="engineUp">引擎运行中 · 能力 {{ capsOk }}/6</template>
      <template v-else>引擎未运行</template>
    </div>
  </div>

  <div class="wrap">
    <div v-if="error" class="card"><div class="empty">{{ error }}</div></div>

    <template v-else-if="stats">
      <div class="grid">
        <div class="stat"><div class="num">{{ stats.keepAdj }}</div><div class="cap">今日保活纠正</div></div>
        <div class="stat"><div class="num">{{ stats.killed }}</div><div class="cap">今日回收</div></div>
        <div class="stat"><div class="num">{{ white.filter(w => w.adj === 200).length }}</div><div class="cap">白名单生效</div></div>
      </div>

      <div class="card">
        <h2>白名单状态</h2>
        <div v-if="!white.length" class="empty">名单为空</div>
        <div v-for="w in white" :key="w.pkg" class="row">
          <div>
            <div class="name">{{ w.pkg }}</div>
            <div class="meta">{{ w.states.join(' · ') || '不在快照' }}</div>
          </div>
          <span class="badge" :class="{ off: w.adj !== 200, warn: w.adj == null }">
            {{ w.adj == null ? '?' : 'adj ' + w.adj }}
          </span>
        </div>
      </div>

      <div class="card">
        <h2>能力探测</h2>
        <div v-for="[k, v] in capsEntries" :key="k" class="row">
          <div class="name">{{ MODE[k] ?? CAP_LABELS[k] ?? k }}</div>
          <span class="badge" :class="{ off: v !== 1 }">{{ v === 1 ? '支持' : '不支持' }}</span>
        </div>
        <div v-if="!capsEntries.length" class="empty">caps.conf 未生成（引擎未启动过）</div>
      </div>

      <div class="card">
        <h2>异常</h2>
        <div class="row"><div class="name">哨兵停机</div>
          <span class="badge" :class="{ off: stats.sentinelHalt > 0 }">{{ stats.sentinelHalt }}</span></div>
        <div class="row"><div class="name">看门狗重启</div>
          <span class="badge" :class="{ off: stats.watchdogRestarts > 0 }">{{ stats.watchdogRestarts }}</span></div>
        <div class="row"><div class="name">名单非法行</div>
          <span class="badge" :class="{ off: stats.listBad > 0 }">{{ stats.listBad }}</span></div>
      </div>

      <div class="card">
        <h2>引擎日志</h2>
        <div v-if="!logTail.length" class="empty">暂无日志</div>
        <div v-for="(l, i) in logTail" :key="i" class="logline"
          :class="{ bad: /SENTINEL|WATCHDOG|halt/.test(l) }">{{ l }}</div>
      </div>
    </template>
  </div>
</template>
