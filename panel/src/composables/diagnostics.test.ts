import { describe, it, expect } from 'vitest'
import { buildDiagCmd } from './diagnostics'

const MOD = '/data/adb/modules/COSMemory'
const LIST = '/sdcard/Android/COSMemory/名单列表.conf'

describe('buildDiagCmd', () => {
  const cmd = buildDiagCmd(MOD, LIST)

  it('输出到 /sdcard/Download 且文件名带时间戳', () => {
    expect(cmd).toContain('OUT="/sdcard/Download/COSMemory_diag_$(date +%Y%m%d-%H%M%S).txt"')
    expect(cmd).toContain('echo "$OUT"')
  })
  it('包含全部诊断段', () => {
    for (const seg of ['==version==', '==device==', '==memory==', '==caps==', '==engine==',
      '==stats_tail80==', '==guard_3d==', '==kill_capture_tail60==', '==snapshot==',
      '==config==', '==list==', '==bridge==', '==cosguard_logcat==', '==lsposed_guard_log=='])
      expect(cmd).toContain(seg)
  })
  it('段标题语句用 "; " 分隔 — 前一条 echo 不会把下一段标题吞成参数', () => {
    const heads = cmd.match(/echo "==[a-z_0-9]+=="/g) ?? []
    expect(heads.length).toBeGreaterThanOrEqual(14)
    for (const h of heads) {
      const idx = cmd.indexOf(h)
      const before = cmd.slice(Math.max(0, idx - 2), idx)
      expect(before).toMatch(/(; |\{ )$/)
    }
  })
  it('单条命令无换行(桥传输安全)', () => expect(cmd.includes('\n')).toBe(false))
  it('引用名单路径含中文时整体加引号', () => expect(cmd).toContain(`cat "${LIST}"`))
})

describe('隐私边界', () => {
  const cmd = buildDiagCmd(MOD, LIST)
  it('logcat 只 grep cosguard|cosmem, 不导全量', () => {
    expect(cmd).toContain('logcat -d')
    const lc = cmd.slice(cmd.indexOf('logcat'))
    expect(lc).toMatch(/grep -iE "cosguard\|cosmem"/)
    expect(lc).not.toContain('> /sdcard')
  })
})
