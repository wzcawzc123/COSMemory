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
    else if (action === 'FREEZE' && target && PKG.test(target)) out.freeze.push(target)
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
