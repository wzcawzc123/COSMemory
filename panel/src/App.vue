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
    const [log, capsTxt, listTxt, parsed, livePid] = await Promise.all([
      execRead(b, `tail -100 ${MOD}/data/stats.log 2>/dev/null`),
      execRead(b, `cat ${MOD}/data/caps.conf 2>/dev/null`),
      execRead(b, `cat "${LIST}" 2>/dev/null`),
      execRead(b, `cat ${MOD}/data/parsed.txt 2>/dev/null`),
      execRead(b, 'pgrep -f engine/memory.sh 2>/dev/null || true'),
    ])
    stats.value = parseStats(log)
    caps.value = parseCaps(capsTxt)
    const wl = listTxt.split('\n').filter(l => l.startsWith('WHITE ')).map(l => l.slice(6).trim()).join(' ')

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

const capsOk = computed(() => Object.values(caps.value).filter(v => v === 1).length)
const capsEntries = computed(() => Object.entries(caps.value))

onMounted(() => { refresh(); timer = window.setInterval(refresh, 5000) })
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
    <div v-if="error" class="alert">{{ error }}</div>

    <template v-else-if="stats">
      <!-- Hero: 引擎状态 -->
      <div class="hero">
        <div class="hero-top">
          <div class="hero-ic"><svg class="si" viewBox="0 0 24 24"><use href="#i-cpu-fill"/></svg></div>
          <div class="hero-tt">
            <div class="t">引擎状态</div>
            <div class="s">ColorOS 16 · 基于 A1Memory 二次开发</div>
          </div>
          <span class="tag" :class="engineUp ? '' : 'off'">
            {{ engineUp ? '运行中' : '已停止' }}
          </span>
        </div>
        <div class="hero-sep" />
        <div class="hero-pills">
          <div class="hp"><div class="n">{{ stats.keepAdj }}</div><div class="l">今日保活</div></div>
          <div class="hp"><div class="n">{{ stats.killed }}</div><div class="l">今日回收</div></div>
          <div class="hp"><div class="n">{{ capsOk }}/6</div><div class="l">能力探测</div></div>
        </div>
      </div>

      <!-- 白名单 -->
      <div class="sec"><div class="b"><svg class="si" viewBox="0 0 24 24"><use href="#i-lock-unlock-fill"/></svg></div><h2>白名单状态</h2></div>
      <div class="card">
        <div v-if="!white.length" class="empty">名单为空</div>
        <div v-for="w in white" :key="w.pkg" class="row">
          <div>
            <div class="name">{{ w.pkg }}</div>
            <div class="meta">{{ w.states.join(' · ') || '不在快照' }}</div>
          </div>
          <span class="pill" :class="w.cchAdj === 200 ? 'ok' : (w.cchAdj === null ? '' : 'bad')">
            {{ w.cchAdj === null ? '系统托管' : 'adj ' + w.cchAdj }}
          </span>
        </div>
      </div>

      <!-- 能力探测: 2x2 方块 -->
      <div class="sec"><div class="b"><svg class="si" viewBox="0 0 24 24"><use href="#i-puzzle-fill"/></svg></div><h2>能力探测</h2></div>
      <div class="grid">
        <div v-for="[k, v] in capsEntries" :key="k" class="tile">
          <div class="th">
            <span class="pill" :class="v === 1 ? 'ok' : 'bad'">{{ v === 1 ? '支持' : '不支持' }}</span>
          </div>
          <div class="ic"><svg class="si" viewBox="0 0 24 24"><use :href="'#' + (CAP_ICON[k] ?? 'i-information-fill')"/></svg></div>
          <div class="t">{{ MODE[k] ?? CAP_LABELS[k] ?? k }}</div>
        </div>
        <div v-if="!capsEntries.length" class="tile">
          <div class="ic">…</div>
          <div class="t">等待引擎</div>
          <div class="s">caps.conf 未生成</div>
        </div>
      </div>

      <!-- 异常 -->
      <div class="sec"><div class="b"><svg class="si" viewBox="0 0 24 24"><use href="#i-information-fill"/></svg></div><h2>异常监控</h2></div>
      <div class="card">
        <div class="row"><div class="name">哨兵停机</div>
          <span class="pill" :class="stats.sentinelHalt > 0 ? 'bad' : 'ok'">{{ stats.sentinelHalt }}</span></div>
        <div class="row"><div class="name">看门狗重启</div>
          <span class="pill" :class="stats.watchdogRestarts > 0 ? 'warn' : 'ok'">{{ stats.watchdogRestarts }}</span></div>
        <div class="row"><div class="name">名单非法行</div>
          <span class="pill" :class="stats.listBad > 0 ? 'warn' : 'ok'">{{ stats.listBad }}</span></div>
        <div class="row"><div class="name">白名单拦截<small style="color:var(--ink2)">（点名杀被拦）</small></div>
          <span class="pill" :class="stats.skipped > 0 ? 'ok' : ''">{{ stats.skipped }}</span></div>
        <div class="row"><div class="name">白名单死亡<small style="color:var(--ink2)">（进程消失事件）</small></div>
          <span class="pill" :class="stats.deaths > 0 ? 'warn' : 'ok'">{{ stats.deaths }}</span></div>
      </div>

      <!-- 日志 -->
      <div class="sec"><div class="b"><svg class="si" viewBox="0 0 24 24"><use href="#i-terminal-box-fill"/></svg></div><h2>引擎日志</h2></div>
      <div class="logbox">
        <div v-if="!logTail.length" class="empty">暂无日志</div>
        <div v-for="(l, i) in logTail" :key="i" class="logline"
          :class="{ bad: /SENTINEL|WATCHDOG|halt/.test(l) }">{{ l }}</div>
      </div>
    </template>
  </div>
</template>
