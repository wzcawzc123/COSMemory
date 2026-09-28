// stats.ts — 解析引擎输出为面板数据 (纯函数, 可测)
export interface DayStats {
  keepAdj: number; killed: number; skips: Record<string, number>
  sentinelHalt: number; watchdogRestarts: number; listBad: number
  engineStarted: boolean; lastLine: string
}
export function emptyStats(): DayStats {
  return { keepAdj: 0, killed: 0, skips: {}, sentinelHalt: 0,
           watchdogRestarts: 0, listBad: 0, engineStarted: false, lastLine: '' }
}
const TS = /^\[(\d{4}-\d{2}-\d{2}) /
export function parseStats(log: string, day = ''): DayStats {
  const s = emptyStats()
  const want = day || new Date().toLocaleDateString('en-CA')
  for (const raw of log.split('\n')) {
    const line = raw.trim()
    if (!line) continue
    const m = line.match(TS)
    if (m) {
      if (m[1] !== want) continue
      if (line.includes('KEEPADJ ')) s.keepAdj++
      else if (line.includes('SENTINEL HALT')) s.sentinelHalt++
      else if (line.includes('WATCHDOG restart')) s.watchdogRestarts++
      else if (line.includes('LIST_BAD')) s.listBad++
      else if (line.includes('START caps')) s.engineStarted = true
      s.lastLine = line
    } else {
      const k = line.match(/KILLED=(\d+)/)
      if (k) s.killed += Number(k[1])
      const sk = line.match(/^SKIP (\S+)/)
      if (sk) s.skips[sk[1]] = (s.skips[sk[1]] ?? 0) + 1
    }
  }
  return s
}
export function parseCaps(text: string): Record<string, number> {
  const out: Record<string, number> = {}
  for (const line of text.split('\n')) {
    const m = line.match(/^(CAP_[A-Z_]+)=(\d)$/)
    if (m) out[m[1]] = Number(m[2])
  }
  return out
}
export const CAP_LABELS: Record<string, string> = {
  CAP_LRU: '进程快照 (dumpsys lru)', CAP_LRU_FALLBACK: '备用快照源',
  CAP_PSI: '内存压力 (PSI)', CAP_ADJ: 'adj 写入',
  CAP_LMKD_CFG: 'lmkd 调参入口', CAP_OPLUS: 'Oplus 扩展',
}
export interface WhiteEntry { pkg: string; adj: number | null; states: string[] }
/** 行格式 state|adj|pkg (面板端 shell 聚合) + WHITE 名单 → 每个白名单包一条 */
export function whiteStatus(rows: string, white: string): WhiteEntry[] {
  const list = white.split(/\s+/).filter(Boolean)
  const map = new Map<string, WhiteEntry>()
  for (const w of list) map.set(w, { pkg: w, adj: null, states: [] })
  for (const line of rows.split('\n')) {
    const [state, adjStr, pkg] = line.split('|')
    if (!pkg) continue
    const key = list.find(w => pkg === w || (!w.includes(':') && pkg.startsWith(w + ':')))
    if (!key) continue
    const e = map.get(key)!
    const a = Number(adjStr)
    if (Number.isFinite(a)) e.adj = e.adj == null ? a : Math.min(e.adj, a)
    if (state && !e.states.includes(state)) e.states.push(state)
  }
  return [...map.values()]
}
