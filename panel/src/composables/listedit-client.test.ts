import { describe, it, expect, vi } from 'vitest'
import { listEdit } from './listedit-client'
import type { KsuBridge } from './ksu'

const b64 = (s: string) => btoa(unescape(encodeURIComponent(s)))
const mk = (out: string) => ({ exec: vi.fn(async () => b64(out)) }) as unknown as KsuBridge

describe('listEdit 协议解析', () => {
  it('OK → ok', async () =>
    expect(await listEdit(mk('OK\n'), '/m', 'add', 'WHITE', 'com.a')).toEqual({ ok: true, err: '' }))
  it('ERR:dup 透传', async () =>
    expect(await listEdit(mk('ERR:dup\n'), '/m', 'del', 'WHITE', 'com.a')).toEqual({ ok: false, err: 'ERR:dup' }))
  it('空输出 → ERR:empty', async () =>
    expect(await listEdit(mk(''), '/m', 'add', 'WHITE', 'com.a')).toEqual({ ok: false, err: 'ERR:empty' }))
  it('OK+WARN 首行判成功', async () =>
    expect((await listEdit(mk('OK\nWARN:bridge\n'), '/m', 'add', 'WHITE', 'com.a')).ok).toBe(true))
  it('非法 target 拒绝且不调 exec', async () => {
    const b = mk('OK')
    const r = await listEdit(b, '/m', 'add', 'WHITE', 'com.a; rm -rf /')
    expect(r).toEqual({ ok: false, err: 'ERR:badfmt' })
    expect((b as any).exec).not.toHaveBeenCalled()
  })
})
