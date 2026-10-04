import { ref } from 'vue'

export interface GuardStats {
  date: string; mode: string; module: string; live_today: boolean
  snapshot_age_s: number; fuse_threshold: number
  today: { block: number; fuse: number; error: number; pass_observe: number }
  hourly: { h: number; block: number; fuse: number }[]
  rules: { rule: string; n: number }[]
  whitelist: { pkg: string; block: number; last_ts: number; last_act: string }[]
  recent: { ts: number; pkg: string; rule: string; act: string; reason: string }[]
  dates: string[]
  freezeToday: number
  reclaimToday: number
  reclaimAggressive: boolean
  reclaimDepth: string
  freezeList: { pkg: string; alive: boolean }[]
}

export const GUARD_NAME: Record<string, string> = {
  'com.tencent.mm': '微信',
  'com.tencent.mobileqq': 'QQ',
  'com.ss.android.ugc.aweme': '抖音',
}
export function guardName(pkg: string): string {
  return GUARD_NAME[pkg] ?? pkg.split('.').pop() ?? pkg
}

/** act 码 → 短中文 (卡片胶囊/事件流); 未知码原样返回, 空值 = 无事件 */
export const ACT_LABEL: Record<string, string> = {
  BLOCK: '已保活',
  FUSE: '保险丝',
  ERROR: '异常',
  PASS_NO_RULE: '放行',
  PASS_DUP: '放行·重复',
  PASS_OBSERVE: '观察',
  FREEZE: '已封杀',
  FREEZE_BLOCK: '已封杀',
  RECLAIM: '已回收',
}
export function actLabel(act: string): string {
  return ACT_LABEL[act] ?? (act || '无事件')
}

const emptyHourly = () => Array.from({ length: 24 }, (_, h) => ({ h, block: 0, fuse: 0 }))

export function parseGuard(json: string): GuardStats | null {
  try {
    const o = JSON.parse(json)
    if (!o || typeof o !== 'object') return null
    return {
      date: String(o.date ?? ''), mode: String(o.mode ?? 'observe'),
      module: String(o.module ?? 'absent'), live_today: !!o.live_today,
      snapshot_age_s: Number(o.snapshot_age_s ?? -1),
      fuse_threshold: Number(o.fuse_threshold ?? 10),
      today: {
        block: Number(o.today?.block ?? 0), fuse: Number(o.today?.fuse ?? 0),
        error: Number(o.today?.error ?? 0), pass_observe: Number(o.today?.pass_observe ?? 0),
      },
      hourly: Array.isArray(o.hourly) && o.hourly.length === 24 ? o.hourly : emptyHourly(),
      rules: Array.isArray(o.rules) ? o.rules : [],
      whitelist: Array.isArray(o.whitelist) ? o.whitelist : [],
      recent: Array.isArray(o.recent) ? o.recent : [],
      dates: Array.isArray(o.dates) ? o.dates.map(String) : [],
      freezeToday: Number(o.freezeToday ?? 0),
      reclaimToday: Number(o.reclaimToday ?? 0),
      reclaimAggressive: !!o.reclaimAggressive,
      reclaimDepth: String(o.reclaimDepth ?? "cached"),
      freezeList: Array.isArray(o.freezeList)
        ? o.freezeList.map((x: { pkg?: unknown; alive?: unknown }) =>
            ({ pkg: String(x?.pkg ?? ''), alive: !!x?.alive })) : [],
    }
  } catch { return null }
}

export const guardDate = ref<string>('')   // 空 = 今天
