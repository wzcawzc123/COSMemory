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

/** 批量往返: ksu.exec 是同步阻塞接口, Promise.all 实为串行 N 次 shell 启动;
 *  多段命令用 @@SEG:key@@ 分隔符合并为一次 base64 往返 (refresh 6次→1次, 数据到位 6s→~1.5s)。 */
export function splitBatch(decoded: string): Record<string, string> {
  const parts = decoded.split(/@@SEG:([a-zA-Z0-9_-]+)@@/g)
  const out: Record<string, string> = {}
  for (let i = 1; i < parts.length; i += 2) out[parts[i]] = (parts[i + 1] ?? '').trim()
  return out
}

export async function execReadBatch(bridge: KsuBridge, cmd: string): Promise<Record<string, string>> {
  return splitBatch(await execRead(bridge, cmd))
}
