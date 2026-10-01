<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import { parseApps, filterApps, iconCmd, parseIcons, type AppEntry } from '../composables/apppicker'
import { detectBridge, execRead } from '../composables/ksu'

const props = defineProps<{ open: boolean }>()
const emit = defineEmits<{ (e: 'close'): void; (e: 'select', pkg: string): void }>()
const apps = ref<AppEntry[]>([])
const icons = ref<Record<string, string>>({})
const q = ref('')
const state = ref<'loading' | 'ok' | 'fallback'>('loading')
const shown = computed(() => filterApps(apps.value, q.value).slice(0, 30))

async function load() {
  state.value = 'loading'
  const b = detectBridge()
  if (!b) { state.value = 'fallback'; return }
  try {
    const raw = await execRead(b, 'cat /data/system/cosmem/apps.json 2>/dev/null')
    apps.value = parseApps(raw)
    if (!apps.value.length) { state.value = 'fallback'; return }
    state.value = 'ok'
    const pkgs = shown.value.map(a => a.p)
    if (pkgs.length) {
      const out = await execRead(b, iconCmd(pkgs)).catch(() => '')
      icons.value = parseIcons(out)
    }
  } catch { state.value = 'fallback' }
}
watch(() => props.open, (v) => { if (v) { q.value = ''; load() } })
watch(q, async () => {
  if (state.value !== 'ok') return
  const b = detectBridge(); if (!b) return
  const pkgs = shown.value.map(a => a.p).filter(p => !icons.value[p])
  if (pkgs.length) {
    const out = await execRead(b, iconCmd(pkgs.slice(0, 30))).catch(() => '')
    Object.assign(icons.value, parseIcons(out))
  }
})
function pick(p: string) { emit('select', p); emit('close') }
</script>

<template>
  <div v-if="open" class="ap-mask" @click.self="emit('close')">
    <div class="ap-box">
      <input v-model="q" placeholder="搜索应用名 / 包名" />
      <div v-if="state === 'fallback'" class="ap-fb">
        应用清单不可用 (AppCatalog 未生成), 请手打包名。
      </div>
      <div v-else-if="state === 'loading'" class="ap-fb">加载中…</div>
      <div v-for="a in shown" :key="a.p" class="ap-row" @click="pick(a.p)">
        <img v-if="icons[a.p]" :src="'data:image/png;base64,' + icons[a.p]" />
        <span v-else class="ap-ph">{{ a.l.slice(0, 1) }}</span>
        <span class="ap-l">{{ a.l }}</span>
        <span class="ap-p">{{ a.p }}</span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.ap-mask{position:fixed;inset:0;background:rgba(0,0,0,.45);z-index:50;display:flex;align-items:flex-end}
.ap-box{background:var(--bg,#fff);width:100%;max-height:70vh;overflow:auto;padding:10px;border-radius:12px 12px 0 0}
.ap-box input{width:100%;box-sizing:border-box;font-size:13px;padding:7px 10px;margin-bottom:6px;
  border:1px solid var(--ink3,#ccc);border-radius:8px;background:var(--bg,#fff);color:var(--ink)}
.ap-row{display:flex;gap:8px;align-items:center;padding:7px 4px;font-size:13px}
.ap-row img{width:26px;height:26px;border-radius:6px}
.ap-ph{width:26px;height:26px;border-radius:6px;background:var(--ink3,#ddd);text-align:center;
  line-height:26px;font-size:12px;color:var(--ink2)}
.ap-l{color:var(--ink)}
.ap-p{color:var(--ink2,#888);font-size:11px;margin-left:auto}
.ap-fb{padding:14px 4px;color:var(--ink2,#888);font-size:12px}
</style>
