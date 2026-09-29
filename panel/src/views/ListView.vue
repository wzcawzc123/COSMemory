<script setup lang="ts">
import { computed } from 'vue'
import { parseListConf } from '../composables/listconf'
import { guardName } from '../composables/guard'

const props = defineProps<{
  white: { pkg: string; adj: number | null; states: string[] }[]
  listRaw: string
}>()
const conf = computed(() => parseListConf(props.listRaw))
const GROUPS = [
  { key: 'white' as const, label: 'WHITE 保活', cls: 'ok' },
  { key: 'kill' as const, label: 'KILL 点名杀', cls: 'warn' },
  { key: 'freeze' as const, label: 'FREEZE 封杀', cls: 'bad' },
]
</script>

<template>
  <!-- 运行时快照 -->
  <div class="sec"><div class="b"><svg class="si" viewBox="0 0 24 24"><use href="#i-user-smile-fill"/></svg></div><h2>白名单快照</h2></div>
  <div class="card">
    <div v-if="!white.length" class="empty">名单为空</div>
    <div v-for="w in white" :key="w.pkg" class="row">
      <div>
        <div class="name">{{ guardName(w.pkg) }}</div>
        <div class="meta">{{ w.pkg }} · {{ w.states.join(' · ') || '不在快照' }}</div>
      </div>
      <span class="pill" :class="w.cchAdj === 200 ? 'ok' : (w.cchAdj === null ? '' : 'bad')">
        {{ w.cchAdj === null ? '系统托管' : 'adj ' + w.cchAdj }}</span>
    </div>
  </div>

  <!-- conf 文件内容 -->
  <div class="sec"><div class="b"><svg class="si" viewBox="0 0 24 24"><use href="#i-file-cloud-fill"/></svg></div><h2>名单配置</h2></div>
  <div class="card">
    <div v-for="g in GROUPS" :key="g.key" class="lc-group">
      <div class="lc-head"><span class="pill" :class="g.cls">{{ g.label }}</span><i>{{ conf[g.key].length }} 条</i></div>
      <div v-if="!conf[g.key].length" class="gd-empty">空</div>
      <div v-for="t in conf[g.key]" :key="t" class="lc-line">{{ t }}</div>
    </div>
    <div v-if="conf.bad.length" class="lc-group">
      <div class="lc-head"><span class="pill bad">非法行 {{ conf.bad.length }}</span></div>
      <div v-for="t in conf.bad" :key="t" class="lc-line lc-bad">{{ t }}</div>
    </div>
    <div v-if="!conf.raw" class="gd-empty">名单文件未读取到</div>
  </div>
</template>

<style scoped>
.lc-group{margin-bottom:10px}
.lc-head{display:flex; align-items:center; gap:8px; margin-bottom:4px}
.lc-head i{font-style:normal; font-size:11px; color:var(--ink2)}
.lc-line{font-family:ui-monospace,Menlo,monospace; font-size:12px; padding:3px 0;
  color:var(--ink); word-break:break-all}
.lc-bad{color:var(--red)}
</style>
