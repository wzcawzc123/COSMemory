import { describe, it, expect } from 'vitest'
import { b64utf8, execRead, detectBridge, splitBatch, execReadBatch } from './ksu'

describe('b64utf8', () => {
  it('解码中文', () => expect(b64utf8('5Lit5paH')).toBe('中文'))
  it('解码多行', () => expect(b64utf8('YQpiCg==')).toBe('a\nb\n'))
  it('容忍缺失padding与换行', () => expect(b64utf8('5Lit5pa\nH')).toBe('中文'))
  it('空串', () => expect(b64utf8('')).toBe(''))
})

describe('execRead', () => {
  it('包一层base64并解码', async () => {
    const bridge = { exec: async (c: string) => { expect(c).toContain('| base64'); return '5Lit5paH' } }
    expect(await execRead(bridge, 'cat /x')).toBe('中文')
  })
  it('空输出返回空串', async () => {
    expect(await execRead({ exec: async () => '   ' }, 'cat /missing')).toBe('')
  })
})

describe('detectBridge', () => {
  it('无桥返回null', () => {
    const g = globalThis as any
    delete g.ksu; delete g.WebUIX; delete g.mmrl
    expect(detectBridge()).toBeNull()
  })
  it('ksu.exec存在时返回桥', async () => {
    const g = globalThis as any
    g.ksu = { exec: async () => 'ok' }
    const b = detectBridge()
    expect(b).not.toBeNull()
    expect(await b!.exec('x')).toBe('ok')
    delete g.ksu
  })
  it('execAsync回调式桥', async () => {
    const g = globalThis as any
    g.ksu = { execAsync: (c: string, cb: (r: string) => void) => cb('async-ok') }
    const b = detectBridge()
    expect(await b!.exec('x')).toBe('async-ok')
    delete g.ksu
  })
})

describe('execRead 管道成组(回归: || 短路bug)', () => {
  it('命令含 || true 时整体被括号包裹', async () => {
    const seen: string[] = []
    const bridge = { exec: async (c: string) => { seen.push(c); return '' } }
    await execRead(bridge, 'pgrep -f x 2>/dev/null || true')
    expect(seen[0]).toBe('(pgrep -f x 2>/dev/null || true) | base64 | tr -d \'\\n\'')
    expect(seen[0].startsWith('(')).toBe(true)
  })
  it('解码明文(短路漏网)时返回空而非乱码', async () => {
    // 若实现退化为明文直出, b64utf8 失败应返回 ''
    const bridge = { exec: async () => '13478\n2322' }
    expect(await execRead(bridge, 'pgrep x || true')).toBe('')
  })
})

describe('splitBatch / execReadBatch', () => {
  it('按 @@SEG:key@@ 切分多段', () => {
    const out = 'before\n@@SEG:log@@\nline1\nline2\n@@SEG:pid@@\n1234\n'
    expect(splitBatch(out)).toEqual({ log: 'line1\nline2', pid: '1234' })
  })
  it('段值 trim, 空段返回空串', () => {
    expect(splitBatch('@@SEG:a@@\n  x  \n@@SEG:b@@\n')).toEqual({ a: 'x', b: '' })
  })
  it('数据含 @@ 不误切', () => {
    expect(splitBatch('@@SEG:a@@\nfoo @@ bar\n')).toEqual({ a: 'foo @@ bar' })
  })
  it('无标记返回空对象', () => expect(splitBatch('plain')).toEqual({}))
  it('execReadBatch 经 base64 解码后切分', async () => {
    const payload = b64utf8 // 复用解码函数保持同源
    const bridge = { exec: async () => Buffer.from('@@SEG:x@@\nY').toString('base64') }
    const r = await execReadBatch(bridge as never, 'cmd')
    expect(r).toEqual({ x: 'Y' })
  })
})
