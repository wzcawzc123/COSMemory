import { describe, it, expect } from 'vitest'
import { parseApps, filterApps, parseIcons } from './apppicker'

const json = '{"v":1,"apps":[{"p":"com.tencent.mm","l":"微信","t":1},{"p":"com.android.settings","l":"Settings","t":0}]}'
describe('parseApps', () => {
  it('解析协议', () => {
    expect(parseApps(json)).toEqual([
      { p: 'com.tencent.mm', l: '微信', t: 1 },
      { p: 'com.android.settings', l: 'Settings', t: 0 },
    ])
  })
  it('坏输入 → []', () => { expect(parseApps('not json')).toEqual([]); expect(parseApps('')).toEqual([]) })
  it('v 不符 → []', () => expect(parseApps('{"v":2,"apps":[]}')).toEqual([]))
})
describe('filterApps', () => {
  const apps = parseApps(json)
  it('按 label 忽略大小写无命中', () => expect(filterApps(apps, 'weixin')).toHaveLength(0))
  it('按 label 中文', () => expect(filterApps(apps, '微信')).toHaveLength(1))
  it('按 pkg 子串', () => expect(filterApps(apps, 'tencent')).toHaveLength(1))
  it('空 query 全量', () => expect(filterApps(apps, '')).toHaveLength(2))
})
describe('parseIcons', () => {
  it('按 ==== 分段解析', () => {
    expect(parseIcons('====com.a\nAAA\n====com.b\nBBB\n')).toEqual({ 'com.a': 'AAA', 'com.b': 'BBB' })
  })
  it('空段跳过', () => expect(parseIcons('')).toEqual({}))
})
