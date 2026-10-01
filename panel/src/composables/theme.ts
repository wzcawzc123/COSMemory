import { ref, computed } from 'vue'
import { detectBridge, execRead } from './ksu'

export type ThemeMode = 'light' | 'dark' | 'system'
const KEY = 'cosmem-theme'
const MOD_THEME = '/data/adb/modules/COSMemory/data/theme'

export function resolveTheme(mode: ThemeMode, sysDark: boolean): 'light' | 'dark' {
  if (mode === 'system') return sysDark ? 'dark' : 'light'
  return mode
}

export function loadMode(): ThemeMode {
  try {
    const v = typeof localStorage !== 'undefined' ? localStorage.getItem(KEY) : null
    if (v === 'light' || v === 'dark' || v === 'system') return v
  } catch { /* ignore */ }
  return 'system'
}

function sysDarkNow(): boolean {
  try { return typeof window !== 'undefined' && !!window.matchMedia
    ? window.matchMedia('(prefers-color-scheme: dark)').matches : false
  } catch { return false }
}

export const themeMode = ref<ThemeMode>(loadMode())
export const systemDark = ref(sysDarkNow())
export const resolvedTheme = computed(() => resolveTheme(themeMode.value, systemDark.value))

export function applyTheme(): void {
  try { document.documentElement.dataset.theme = resolvedTheme.value } catch { /* test env */ }
}

export function setTheme(m: ThemeMode): void {
  themeMode.value = m
  try { localStorage.setItem(KEY, m) } catch { /* ignore */ }
  applyTheme()
  persistThemeToModule(m)
}

// 模块侧持久化: 单一源头 = 模块 data/theme 文件。
// 覆盖安装随 data/ 迁移保留; 卸载即消失 → 重装回出厂 (localStorage 仅作同会话缓存/无桥回退)
export function persistThemeToModule(m: ThemeMode): void {
  try {
    const b = detectBridge()
    if (b) void execRead(b, `printf '%s' '${m}' > ${MOD_THEME} 2>/dev/null || true`)
  } catch { /* ignore */ }
}

// 启动对账 (App onMounted): 模块侧为准; 侧文件缺失 = 全新安装/卸载重装 → 清残留回出厂 system
export async function syncThemeFromModule(): Promise<void> {
  let b: ReturnType<typeof detectBridge> = null
  try { b = detectBridge() } catch { /* ignore */ }
  if (!b) return
  const v = (await execRead(b, `cat ${MOD_THEME} 2>/dev/null`)).trim()
  if (v === 'light' || v === 'dark' || v === 'system') {
    if (v !== themeMode.value) { themeMode.value = v; applyTheme() }
  } else {
    if (themeMode.value !== 'system') { themeMode.value = 'system'; applyTheme() }
    try { localStorage.removeItem(KEY) } catch { /* ignore */ }
  }
}

/** App onMounted 调用: 应用当前主题 + 监听系统切换(仅 system 模式跟随) */
export function initTheme(): void {
  applyTheme()
  try {
    window.matchMedia('(prefers-color-scheme: dark)')
      .addEventListener('change', (e) => {
        systemDark.value = e.matches
        if (themeMode.value === 'system') applyTheme()
      })
  } catch { /* ignore */ }
}
