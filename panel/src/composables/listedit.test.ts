import { describe, it, expect } from 'vitest'
import { parseListConf, validateEdit, buildTarget } from './listconf'

const conf = parseListConf(['{', 'WHITE com.a', 'FREEZE com.b:group-black', 'KILL com.c:push', '}'].join('\n'))

describe('parseListConf FREEZE 带组 (对齐 awk)', () => {
  it('FREEZE pkg:group 不再判非法', () => {
    expect(conf.freeze).toContain('com.b:group-black')
    expect(conf.bad).not.toContain('FREEZE')
  })
})

describe('validateEdit', () => {
  it('WHITE 同包 dup', () => expect(validateEdit('white', 'com.a', conf)).toBe('dup'))
  it('FREEZE 包级 dup (剥组)', () => expect(validateEdit('freeze', 'com.b', conf)).toBe('dup'))
  it('D4 包名级: freeze 目标已在 white', () =>
    expect(validateEdit('freeze', 'com.a:grp', conf)).toBe('conflict'))
  it('D4 反向: white 目标已在 freeze', () =>
    expect(validateEdit('white', 'com.b', conf)).toBe('conflict'))
  it('KILL 无后缀 badfmt', () => expect(validateEdit('kill', 'com.c', conf)).toBe('badfmt'))
  it('KILL 同后缀 dup (整串)', () => expect(validateEdit('kill', 'com.c:push', conf)).toBe('dup'))
  it('KILL 不同后缀允许', () => expect(validateEdit('kill', 'com.c:fg', conf)).toBe(''))
  it('空白 badfmt', () => expect(validateEdit('white', 'bad pkg', conf)).toBe('badfmt'))
  it('首字符数字 badfmt', () => expect(validateEdit('white', '1bad', conf)).toBe('badfmt'))
  it('新包通过', () => expect(validateEdit('white', 'com.d', conf)).toBe(''))
})

describe('buildTarget', () => {
  it('KILL 拼后缀去重复冒号', () => expect(buildTarget('kill', 'com.c', ':push')).toBe('com.c:push'))
  it('KILL 拼接基本形', () => expect(buildTarget('kill', 'com.c', 'push')).toBe('com.c:push'))
  it('FREEZE 带组', () => expect(buildTarget('freeze', 'com.g', 'group-black')).toBe('com.g:group-black'))
  it('FREEZE 无组', () => expect(buildTarget('freeze', 'com.g', '')).toBe('com.g'))
  it('WHITE 忽略后缀', () => expect(buildTarget('white', 'com.w', 'x')).toBe('com.w'))
})
