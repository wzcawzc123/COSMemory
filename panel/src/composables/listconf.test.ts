import { describe, it, expect } from 'vitest'
import { parseListConf } from './listconf'

const SAMPLE = `# 出厂名单
{
WHITE com.tencent.mm
WHITE com.tencent.mobileqq
KILL com.tencent.mm:toolsmp
FREEZE com.bloat.app
bad_line_without_action
WHITE
}
`
describe('parseListConf', () => {
  it('splits by action with lists.sh validity rules', () => {
    const c = parseListConf(SAMPLE)
    expect(c.white).toEqual(['com.tencent.mm', 'com.tencent.mobileqq'])
    expect(c.kill).toEqual(['com.tencent.mm:toolsmp'])
    expect(c.freeze).toEqual(['com.bloat.app'])
    expect(c.bad).toEqual(['bad_line_without_action', 'WHITE'])
  })
  it('empty input', () => {
    const c = parseListConf('')
    expect(c.white).toEqual([]); expect(c.bad).toEqual([])
  })
})

describe('D4 WHITE∩FREEZE conflict', () => {
  it('conflict pkg goes to bad and leaves both lists', () => {
    const c = parseListConf('WHITE com.a\nWHITE com.t\nFREEZE com.a\nFREEZE com.b\n')
    expect(c.bad).toContain('com.a')
    expect(c.white).not.toContain('com.a')
    expect(c.freeze).not.toContain('com.a')
    expect(c.freeze).toContain('com.b')
    expect(c.white).toContain('com.t')
  })
})
