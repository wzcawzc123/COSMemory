import { describe, it, expect, beforeEach, vi } from 'vitest'
import { resolveTheme, setTheme, loadMode, syncThemeFromModule, themeMode } from './theme'

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

describe('模块侧主题同步 (覆盖安装保留 / 卸载重装回出厂)', () => {
  const B64 = { system: 'c3lzdGVt', dark: 'ZGFyaw==', light: 'bGlnaHQ=' }
  beforeEach(() => {
    mem.clear()
    themeMode.value = 'system'
    ;(globalThis as any).ksu = undefined
  })

  it('模块侧有值 → 以模块侧为准覆盖本地', async () => {
    ;(globalThis as any).ksu = { exec: async (c: string) => c.includes('cat ') ? B64.system : '' }
    themeMode.value = 'dark'
    await syncThemeFromModule()
    expect(themeMode.value).toBe('system')
  })

  it('模块侧文件缺失(全新安装/卸载重装) → 回出厂 system 并清 localStorage 残留', async () => {
    ;(globalThis as any).ksu = { exec: async () => '' }
    themeMode.value = 'dark'
    mem.set('cosmem-theme', 'dark')
    await syncThemeFromModule()
    expect(themeMode.value).toBe('system')
    expect(mem.has('cosmem-theme')).toBe(false)
  })

  it('无桥 → 保留现状不误重置', async () => {
    themeMode.value = 'dark'
    mem.set('cosmem-theme', 'dark')
    await syncThemeFromModule()
    expect(themeMode.value).toBe('dark')
    expect(mem.has('cosmem-theme')).toBe(true)
  })

  it('setTheme 同步写模块侧文件 (printf > data/theme)', async () => {
    const seen: string[] = []
    ;(globalThis as any).ksu = { exec: async (c: string) => { seen.push(c); return '' } }
    setTheme('dark')
    await Promise.resolve()
    expect(seen.some(c => c.includes('data/theme') && c.includes('printf'))).toBe(true)
  })
})
