import { describe, it, expect } from 'vitest'
import { parseMemtop, parseFrozen, fmtKB, shortPkg } from './memview'

describe('parseMemtop', () => {
  it('正常单行', () => {
    const r = parseMemtop('OK:com.tencent.mm=1074332|com.sankuai.meituan=805104|system=502530')
    expect(r).toHaveLength(3)
    expect(r[0]).toEqual({ pkg: 'com.tencent.mm', kb: 1074332 })
    expect(r[2].pkg).toBe('system')
  })
  it('乱序输入按 kb 降序', () => {
    const r = parseMemtop('OK:a=10|b=99|c=50')
    expect(r.map(x => x.kb)).toEqual([99, 50, 10])
  })
  it('OK:空 → []', () => expect(parseMemtop('OK:空')).toEqual([]))
  it('无前缀/空串 → []', () => {
    expect(parseMemtop('garbage')).toEqual([])
    expect(parseMemtop('')).toEqual([])
    expect(parseMemtop('ERROR:x=1')).toEqual([])
  })
  it('坏段跳过不炸', () => {
    const r = parseMemtop('OK:a=10|b=xx|=5|c=30')
    expect(r.map(x => x.pkg)).toEqual(['c', 'a'])
  })
})

describe('parseFrozen', () => {
  it('正常', () => {
    const r = parseFrozen('OK:3|com.a,com.b,com.c')
    expect(r).toEqual({ count: 3, pkgs: ['com.a', 'com.b', 'com.c'] })
  })
  it('零冻结', () => expect(parseFrozen('OK:0|无')).toEqual({ count: 0, pkgs: [] }))
  it('负数=解析失败', () => expect(parseFrozen('x').count).toBe(-1))
})

describe('fmtKB', () => {
  it('GB', () => expect(fmtKB(1338480)).toBe('1.3G'))
  it('MB', () => expect(fmtKB(408640)).toBe('399M'))
  it('KB', () => expect(fmtKB(512)).toBe('512K'))
})

describe('shortPkg', () => {
  it('主包', () => expect(shortPkg('com.sankuai.meituan')).toBe('meituan'))
  it('子进程', () => expect(shortPkg('com.tencent.mm:push')).toBe('mm:push'))
})
