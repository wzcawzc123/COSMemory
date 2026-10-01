export interface AppEntry { p: string; l: string; t: number }

export function parseApps(json: string): AppEntry[] {
  try {
    const o = JSON.parse(json)
    if (!o || o.v !== 1 || !Array.isArray(o.apps)) return []
    return o.apps.filter((a: any) => a && typeof a.p === 'string' && typeof a.l === 'string')
      .map((a: any) => ({ p: a.p, l: a.l, t: a.t ? 1 : 0 }))
  } catch { return [] }
}

export function filterApps(apps: AppEntry[], q: string): AppEntry[] {
  const s = q.trim().toLowerCase()
  if (!s) return apps
  return apps.filter(a => a.l.toLowerCase().includes(s) || a.p.toLowerCase().includes(s))
}

/** 首屏 icon 批量取: 单次 exec 输出 "====<pkg>\n<base64>" 分段 (spec §4.4 ≤2 exec 约束) */
export function iconCmd(pkgs: string[]): string {
  const dir = '/data/system/cosmem/icons'
  return pkgs.map(p => `echo ====${p}; base64 -w0 ${dir}/${p}.png 2>/dev/null; echo`).join('; ')
}

export function parseIcons(out: string): Record<string, string> {
  const m: Record<string, string> = {}
  for (const seg of out.split('====').slice(1)) {
    const nl = seg.indexOf('\n')
    if (nl > 0) {
      const pkg = seg.slice(0, nl).trim()
      const b = seg.slice(nl + 1).trim()
      if (pkg && b) m[pkg] = b
    }
  }
  return m
}
