import { ref, computed } from 'vue'

export type ThemeMode = 'light' | 'dark' | 'system'
const KEY = 'cosmem-theme'

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
