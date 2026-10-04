import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

/** 回归: st-diag 样式曾被写到 </style> 之外导致整段失效(按钮渲染成浏览器默认灰样式). */
describe('SettingsView 样式完整性', () => {
  const src = readFileSync(fileURLToPath(new URL('./SettingsView.vue', import.meta.url)), 'utf-8')

  it('.st-diag 规则位于 </style> 之前', () => {
    const styleEnd = src.indexOf('</style>')
    const diagRule = src.indexOf('.st-diag{')
    expect(styleEnd).toBeGreaterThan(0)
    expect(diagRule).toBeGreaterThan(0)
    expect(diagRule).toBeLessThan(styleEnd)
  })

  it('文件中 </style> 之后不存在任何选择器规则', () => {
    const after = src.slice(src.indexOf('</style>') + '</style>'.length)
    expect(after.trim()).toBe('')
  })
})
