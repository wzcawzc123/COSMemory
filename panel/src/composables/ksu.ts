export interface KsuBridge { exec(cmd: string): Promise<string> }

declare global {
  interface Window {
    ksu?: { exec?: (cmd: string) => Promise<string>; execAsync?: (cmd: string, cb: (r: string) => void) => void }
    WebUIX?: { exec?: (cmd: string) => Promise<string> }
    mmrl?: { exec?: (cmd: string) => Promise<string> }
  }
}

export function detectBridge(): KsuBridge | null {
  const w = globalThis as any
  const owner = [w.ksu, w.WebUIX, w.mmrl].find(o => typeof o?.exec === 'function')
  if (owner) return { exec: async (c) => String((await owner.exec(c)) ?? '') }
  if (typeof w.ksu?.execAsync === 'function') {
    return { exec: (c) => new Promise((res, rej) => {
      try { w.ksu.execAsync(c, (r: string) => res(r ?? '')) } catch (e) { rej(e) }
    }) }
  }
  return null
}

export function b64utf8(b64: string): string {
  const s = b64.replace(/\s+/g, '')
  if (!s) return ''
  const bin = atob(s)
  const bytes = Uint8Array.from(bin, (ch) => ch.charCodeAt(0))
  return new TextDecoder('utf-8').decode(bytes)
}

export async function execRead(bridge: KsuBridge, cmd: string): Promise<string> {
  // 成组再管道: 避免 `cmd || true | base64` 的 || 短路导致明文直出
  const out = await bridge.exec("(" + cmd + ") | base64 | tr -d '\\n'")
  if (!out.trim()) return ''
  try { return b64utf8(out) } catch { return '' }
}
