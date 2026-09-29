import { describe, it, expect, beforeEach, vi } from 'vitest'
import { resolveTheme, setTheme, loadMode } from './theme'

// node 环境无 localStorage/document — 最小 stub(零新依赖, 不引 jsdom)
const mem = new Map<string, string>()
vi.stubGlobal('localStorage', {
  getItem: (k: string) => (mem.has(k) ? mem.get(k)! : null),
  setItem: (k: string, v: string) => { mem.set(k, v) },
  removeItem: (k: string) => { mem.delete(k) },
  clear: () => { mem.clear() },
})
const ds: Record<string, string | undefined> = {}
vi.stubGlobal('document', { documentElement: { dataset: ds } })

describe('resolveTheme', () => {
  it('system follows system', () => {
    expect(resolveTheme('system', true)).toBe('dark')
    expect(resolveTheme('system', false)).toBe('light')
  })
  it('forced modes ignore system', () => {
    expect(resolveTheme('dark', false)).toBe('dark')
    expect(resolveTheme('light', true)).toBe('light')
  })
})
describe('setTheme persistence', () => {
  beforeEach(() => mem.clear())
  it('persists and applies to html dataset', () => {
    setTheme('dark')
    expect(mem.get('cosmem-theme')).toBe('dark')
    expect(ds.theme).toBe('dark')
    setTheme('light')
    expect(ds.theme).toBe('light')
  })
  it('loadMode reads persisted / defaults system', () => {
    expect(loadMode()).toBe('system')
    mem.set('cosmem-theme', 'dark')
    expect(loadMode()).toBe('dark')
    mem.set('cosmem-theme', 'junk')
    expect(loadMode()).toBe('system')
  })
})
