// memview.ts — 面板增强包 v1.1.0: 内存占用/冻结观测解析层
export interface MemRow { pkg: string; kb: number }

/** 解析 memtop.sh 单行输出: OK:<pkg>=<KB>|<pkg>=<KB>... → rows (坏格式返回 []) */
export function parseMemtop(s: string): MemRow[] {
  const t = s.trim()
  if (!t.startsWith('OK:')) return []
  const body = t.slice(3)
  if (!body || body === '空') return []
  const rows: MemRow[] = []
  for (const seg of body.split('|')) {
    const i = seg.lastIndexOf('=')
    if (i <= 0) continue
    const kb = Number(seg.slice(i + 1))
    if (!Number.isFinite(kb) || kb < 0) continue
    rows.push({ pkg: seg.slice(0, i), kb })
  }
  return rows.sort((a, b) => b.kb - a.kb)
}

/** 解析 frozencap.sh 单行输出: OK:<N>|<pkg1>,<pkg2>... */
export function parseFrozen(s: string): { count: number; pkgs: string[] } {
  const t = s.trim()
  if (!t.startsWith('OK:')) return { count: -1, pkgs: [] }
  const body = t.slice(3)
  const bar = body.indexOf('|')
  const n = Number(bar < 0 ? body : body.slice(0, bar))
  if (!Number.isFinite(n) || n < 0) return { count: -1, pkgs: [] }
  const rest = bar < 0 ? '' : body.slice(bar + 1)
  const pkgs = (!rest || rest === '无') ? [] : rest.split(',').filter(Boolean)
  return { count: n, pkgs }
}

/** KB → 人话: 1338480→1.3G, 408640→399M, 512→512K */
export function fmtKB(kb: number): string {
  if (kb >= 1048576) return (kb / 1048576).toFixed(1) + 'G'
  if (kb >= 1024) return Math.round(kb / 1024) + 'M'
  return Math.round(kb) + 'K'
}

/** 包名取短名: com.sankuai.meituan → meituan (保留子进程段语义时用原名) */
export function shortPkg(pkg: string): string {
  const [name, sub] = pkg.split(':')
  const base = name.split('.').pop() ?? name
  return sub ? `${base}:${sub}` : base
}
