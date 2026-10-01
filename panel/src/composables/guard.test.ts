import { describe, it, expect } from 'vitest'
import { parseGuard, guardName } from './guard'

const FULL = JSON.stringify({
  date: '2026-09-30', mode: 'guard', module: 'installed', live_today: true,
  snapshot_age_s: 42, fuse_threshold: 10,
  today: { block: 12, fuse: 1, error: 0, pass_observe: 5 },
  hourly: Array.from({ length: 24 }, (_, h) => ({ h, block: h === 3 ? 4 : 0, fuse: 0 })),
  rules: [{ rule: 'o-stop', n: 8 }],
  whitelist: [{ pkg: 'com.tencent.mm', block: 6, last_ts: 1790678523, last_act: 'BLOCK' }],
  recent: [{ ts: 1, pkg: 'com.tencent.mm', rule: 'o-stop', act: 'BLOCK', reason: 'x' }],
  dates: ['2026-09-30'],
})

describe('parseGuard', () => {
  it('parses full payload', () => {
    const g = parseGuard(FULL)!
    expect(g.mode).toBe('guard')
    expect(g.today.block).toBe(12)
    expect(g.hourly).toHaveLength(24)
    expect(g.whitelist[0].pkg).toBe('com.tencent.mm')
    expect(g.dates).toEqual(['2026-09-30'])
  })
  it('returns null on garbage', () => {
    expect(parseGuard('not json')).toBeNull()
    expect(parseGuard('')).toBeNull()
    expect(parseGuard('null')).toBeNull()
  })
  it('fills defaults on missing fields', () => {
    const g = parseGuard('{}')!
    expect(g.mode).toBe('observe')
    expect(g.today.block).toBe(0)
    expect(g.hourly).toHaveLength(24)
    expect(g.recent).toEqual([])
  })
  it('replaces malformed hourly', () => {
    expect(parseGuard(JSON.stringify({ hourly: [1, 2] }))!.hourly).toHaveLength(24)
  })
})
describe('guardName', () => {
  it('maps known whitelist', () => {
    expect(guardName('com.tencent.mm')).toBe('微信')
    expect(guardName('com.tencent.mobileqq')).toBe('QQ')
    expect(guardName('com.ss.android.ugc.aweme')).toBe('抖音')
  })
  it('falls back to last segment', () => {
    expect(guardName('com.foo.bar')).toBe('bar')
  })
})

describe('freeze fields', () => {
  it('parses freezeToday/freezeList', () => {
    const g = parseGuard('{"date":"d","mode":"guard","freezeToday":3,' +
      '"freezeList":[{"pkg":"com.a","alive":true},{"pkg":"com.b","alive":false}]}')!
    expect(g.freezeToday).toBe(3)
    expect(g.freezeList).toEqual([{ pkg: 'com.a', alive: true }, { pkg: 'com.b', alive: false }])
  })
  it('defaults empty when absent', () => {
    const g = parseGuard('{"date":"d","mode":"observe"}')!
    expect(g.freezeToday).toBe(0)
    expect(g.freezeList).toEqual([])
  })
})

describe('reclaim field', () => {
  it('parses reclaimToday', () => {
    const g = parseGuard('{"date":"d","mode":"guard","reclaimToday":4}')!
    expect(g.reclaimToday).toBe(4)
  })
  it('defaults 0', () => {
    expect(parseGuard('{"date":"d"}')!.reclaimToday).toBe(0)
  })
  it('parses aggressive/depth display', () => {
    const g = parseGuard('{"date":"d","reclaimAggressive":true,"reclaimDepth":"previous"}')!
    expect(g.reclaimAggressive).toBe(true)
    expect(g.reclaimDepth).toBe('previous')
  })
})
