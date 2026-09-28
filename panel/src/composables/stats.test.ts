import { describe, it, expect } from 'vitest'
import { parseStats, parseCaps, whiteStatus, emptyStats, CAP_LABELS } from './stats'
const today = new Date().toLocaleDateString('en-CA')

describe('parseStats', () => {
  it('统计当日 KEEPADJ/WATCHDOG/SKIP/KILLED', () => {
    const log = [
      `[${today} 10:00:00] START caps: CAP_LRU=1`,
      `[${today} 10:00:01] KEEPADJ com.tencent.mm 905->200`,
      `[${today} 10:00:02] KEEPADJ com.tencent.mm 925->200`,
      `[${today} 10:00:03] WATCHDOG restart`,
      `APPLIED=1 KILLED=2 FAILED=0`,
      `SKIP cooldown com.x:p`, `SKIP cap com.y:p`,
    ].join('\n')
    const s = parseStats(log)
    expect(s.keepAdj).toBe(2)
    expect(s.killed).toBe(2)
    expect(s.watchdogRestarts).toBe(1)
    expect(s.engineStarted).toBe(true)
    expect(s.skips).toEqual({ cooldown: 1, cap: 1 })
  })
  it('忽略非当日行', () => {
    const s = parseStats(`[2020-01-01 10:00:00] KEEPADJ com.a 1->2`)
    expect(s.keepAdj).toBe(0)
    expect(s).toEqual(emptyStats())
  })
  it('SENTINEL HALT 与 LIST_BAD 计数', () => {
    const s = parseStats(`[${today} 01:00:00] SENTINEL HALT rate=30\n[${today} 01:01:00] LIST_BAD=2 detail=x`)
    expect(s.sentinelHalt).toBe(1)
    expect(s.listBad).toBe(1)
    expect(s.engineStarted).toBe(false)
  })
})

describe('parseCaps', () => {
  it('解析', () => {
    const c = parseCaps('CAP_LRU=1\nCAP_PSI=0\n\njunk')
    expect(c.CAP_LRU).toBe(1); expect(c.CAP_PSI).toBe(0)
    expect(Object.keys(c)).toHaveLength(2)
  })
  it('六项能力都有中文标签', () => {
    for (const k of ['CAP_LRU','CAP_LRU_FALLBACK','CAP_PSI','CAP_ADJ','CAP_LMKD_CFG','CAP_OPLUS'])
      expect(CAP_LABELS[k]).toBeTruthy()
  })
})

describe('whiteStatus', () => {
  it('白名单分组+最严state+最小adj', () => {
    const rows = ['cch|905|com.tencent.mm','svc|500|com.tencent.mm:push',
                  'fg|0|com.tencent.mm','cch|925|com.tencent.mobileqq',
                  'cch|100|not.in.list'].join('\n')
    const w = whiteStatus(rows, 'com.tencent.mm com.tencent.mobileqq')
    expect(w).toHaveLength(2)
    const mm = w.find(e => e.pkg === 'com.tencent.mm')!
    expect(mm.adj).toBe(0)
    expect(mm.states).toEqual(['cch', 'svc', 'fg'])
    expect(mm.cchAdj).toBe(905)   // 缓存态最小adj(引擎管的那类); fg=0不计入
    const qq = w.find(e => e.pkg === 'com.tencent.mobileqq')!
    expect(qq.adj).toBe(925)
    expect(qq.cchAdj).toBe(925)
  })
  it('名单内但快照没有 → 占位保留', () => {
    expect(whiteStatus('', 'com.a')).toEqual([{ pkg: 'com.a', adj: null, cchAdj: null, states: [] }])
  })
  it('WHITE带冒号只精确匹配', () => {
    const w = whiteStatus('cch|10|com.a:sub', 'com.a:sub com.b')
    expect(w[0].cchAdj).toBe(10)
    expect(w[1].cchAdj).toBeNull()
  })
})
