import { execRead, type KsuBridge } from './ksu'

export type EditOp = 'add' | 'del'
export type EditGroup = 'WHITE' | 'KILL' | 'FREEZE'
export interface EditResult { ok: boolean; err: string }

const SAFE = /^[a-zA-Z0-9._:]+$/   // 白名单防注入 (与 listedit.sh validate 同集)

export async function listEdit(
  bridge: KsuBridge, mod: string, op: EditOp, group: EditGroup, target: string
): Promise<EditResult> {
  if (!SAFE.test(target)) return { ok: false, err: 'ERR:badfmt' }
  try {
    const out = await execRead(bridge, `sh ${mod}/engine/listedit.sh ${op} ${group} ${target}`)
    const first = out.split('\n')[0].trim()
    if (first === 'OK') return { ok: true, err: '' }
    return { ok: false, err: first || 'ERR:empty' }
  } catch {
    return { ok: false, err: 'ERR:empty' }
  }
}
