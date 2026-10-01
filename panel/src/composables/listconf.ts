/** 名单 conf 解析(与 engine/lists.sh awk 规则同源: 注释/花括号跳过, 合法性同正则) */
export interface ListConf {
  white: string[]; kill: string[]; freeze: string[]; bad: string[]; raw: string
}
const PKG = /^[a-zA-Z][a-zA-Z0-9._]+$/
const PKG_SUB = /^[a-zA-Z][a-zA-Z0-9._]+:.+$/

export function parseListConf(raw: string): ListConf {
  const out: ListConf = { white: [], kill: [], freeze: [], bad: [], raw }
  for (const line of raw.split('\n')) {
    const t = line.trim()
    if (!t || t.startsWith('#') || t === '{' || t === '}') continue
    const [action, target] = t.split(/\s+/)
    if (action === 'WHITE' && target && PKG.test(target)) out.white.push(target)
    else if (action === 'KILL' && target && PKG_SUB.test(target)) out.kill.push(target)
    else if (action === 'FREEZE' && target && FREEZE_FULL.test(target)) out.freeze.push(target)
    else out.bad.push(t)
  }
  // D4: WHITE∩FREEZE 双向拒绝 — 与 engine/lists.sh awk 规则同源
  const conflict = out.white.filter(w => out.freeze.includes(w))
  if (conflict.length) {
    out.white = out.white.filter(w => !conflict.includes(w))
    out.freeze = out.freeze.filter(f => !conflict.includes(f))
    out.bad.push(...conflict)
  }
  return out
}

/** 对齐 awk FREEZE 规则: pkg 或 pkg:group (spec list-editor §4.1) */
export const FREEZE_FULL = /^[a-zA-Z][a-zA-Z0-9._]+(:.+)?$/
export type ListGroup = 'white' | 'kill' | 'freeze'
export type EditErr = '' | 'badfmt' | 'dup' | 'conflict'

/**
 * 编辑校验: 格式 → 重复 → D4 冲突 (包名级, 比 awk 整串更严 — 前端友好拦截)。
 * dup 语义分组: kill 按整串 (同包不同进程后缀是不同目标), white/freeze 按剥组包名。
 */
export function validateEdit(group: ListGroup, target: string, conf: ListConf): EditErr {
  const re = group === 'kill' ? PKG_SUB : group === 'freeze' ? FREEZE_FULL : PKG
  if (!re.test(target)) return 'badfmt'
  const pkg = target.split(':')[0]
  if (group === 'kill') {
    if (conf.kill.includes(target)) return 'dup'
    return ''
  }
  if (conf[group].some(o => o.split(':')[0] === pkg)) return 'dup'
  const other = group === 'freeze' ? conf.white : conf.freeze
  if (other.some(o => o.split(':')[0] === pkg)) return 'conflict'
  return ''
}

/** 表单三字段 → conf target (KILL 后缀必填由 validateEdit 把关) */
export function buildTarget(group: ListGroup, pkg: string, suffix: string): string {
  const s = suffix.replace(/^:+/, '')
  if (group === 'kill') return `${pkg}:${s}`
  if (group === 'freeze' && s) return `${pkg}:${s}`
  return pkg
}
