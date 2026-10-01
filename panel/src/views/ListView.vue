<script setup lang="ts">
import { ref, computed } from 'vue'
import { parseListConf, validateEdit, buildTarget, type ListGroup } from '../composables/listconf'
import { detectBridge } from '../composables/ksu'
import { listEdit } from '../composables/listedit-client'
import { guardName } from '../composables/guard'
import AppPicker from '../components/AppPicker.vue'

const props = defineProps<{
  white: { pkg: string; adj: number | null; states: string[] }[]
  listRaw: string
  freezeList?: { pkg: string; alive: boolean }[]
  mod: string
}>()
const emit = defineEmits<{ (e: 'edited'): void }>()

const fzOf = (p: string) => props.freezeList?.find(x => x.pkg === p)
const conf = computed(() => parseListConf(props.listRaw))
const GROUPS = [
  { key: 'white' as const, label: 'WHITE 保活', cls: 'ok' },
  { key: 'kill' as const, label: 'KILL 点名杀', cls: 'warn' },
  { key: 'freeze' as const, label: 'FREEZE 封杀', cls: 'bad' },
]

// --- 编辑模式 (spec list-editor §4.1) ---
const editing = ref(false); const busy = ref(false); const err = ref('')
const adding = ref<ListGroup | null>(null)
const formPkg = ref(''); const formSuffix = ref(''); const formErr = ref('')
const confirming = ref('')   // `${group}:${target}`
const picker = ref(false)

async function apply(op: 'add' | 'del', g: ListGroup, target: string): Promise<boolean> {
  const b = detectBridge()
  if (!b) { err.value = 'ERR:no-bridge'; return false }
  busy.value = true; err.value = ''
  const r = await listEdit(b, props.mod, op, g.toUpperCase() as 'WHITE' | 'KILL' | 'FREEZE', target)
  busy.value = false
  if (!r.ok) { err.value = r.err; return false }
  emit('edited'); return true
}
async function submitAdd() {
  const g = adding.value; if (!g) return
  const target = buildTarget(g, formPkg.value.trim(), formSuffix.value.trim())
  formErr.value = validateEdit(g, target, conf.value)
  if (formErr.value) return
  if (await apply('add', g, target)) { adding.value = null; formPkg.value = ''; formSuffix.value = '' }
}
async function doDel(g: ListGroup, t: string) {
  if (await apply('del', g, t)) confirming.value = ''
}
function askDel(g: ListGroup, t: string) { confirming.value = `${g}:${t}` }
function toggleEdit() {
  editing.value = !editing.value
  adding.value = null; err.value = ''; confirming.value = ''; formErr.value = ''
}
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
  <div class="card lc-card">
    <div class="lc-topbar">
      <span class="lc-err" v-if="err">{{ err }}</span>
      <button class="lc-edit" @click="toggleEdit">{{ editing ? '完成' : '编辑' }}</button>
    </div>
    <div v-for="g in GROUPS" :key="g.key" class="lc-group">
      <div class="lc-head"><span class="pill" :class="g.cls">{{ g.label }}</span><i>{{ conf[g.key].length }} 条</i></div>
      <div v-if="!conf[g.key].length" class="gd-empty">空</div>
      <div v-for="t in conf[g.key]" :key="t" class="lc-line">{{ t }}
        <span v-if="g.key === 'freeze' && fzOf(t)" class="pill"
          :class="fzOf(t)!.alive ? 'ok' : 'warn'">{{ fzOf(t)!.alive ? '存活' : '离线' }}</span>
        <span v-if="editing" class="lc-act">
          <template v-if="confirming === g.key + ':' + t">
            <button class="lc-danger" @click="doDel(g.key, t)" :disabled="busy">确认删</button>
            <button @click="confirming = ''">取消</button>
          </template>
          <button v-else @click="askDel(g.key, t)">删除</button>
        </span>
      </div>
      <div v-if="editing" class="lc-addbar">
        <button v-if="adding !== g.key" @click="adding = g.key; formErr = ''">+ 新增</button>
        <div v-else class="lc-form">
          <input v-model="formPkg" placeholder="包名 com.xx.yy" />
          <input v-if="g.key !== 'white'" v-model="formSuffix"
                 :placeholder="g.key === 'kill' ? '进程后缀 :push' : '组 (可选) :group-black'" />
          <button @click="picker = true" :disabled="busy">从已装应用选</button>
          <button @click="submitAdd" :disabled="busy">确定</button>
          <button @click="adding = null">取消</button>
          <div class="lc-err lc-formerr" v-if="formErr">校验: {{ formErr }}</div>
        </div>
      </div>
    </div>
    <div v-if="conf.bad.length" class="lc-group">
      <div class="lc-head"><span class="pill bad">非法行 {{ conf.bad.length }}</span></div>
      <div v-for="t in conf.bad" :key="t" class="lc-line lc-bad">{{ t }}</div>
    </div>
    <div v-if="!conf.raw" class="gd-empty">名单文件未读取到</div>
    <AppPicker :open="picker" @close="picker = false"
      @select="(pk) => { formPkg = pk; formErr = ''; picker = false }" />
  </div>
</template>

<style scoped>
.lc-card{position:relative}
.lc-topbar{display:flex; justify-content:flex-end; min-height:8px}
.lc-edit{position:absolute; right:10px; top:-38px; padding:4px 14px; font-size:12px;
  border:1px solid var(--ink3,#ccc); border-radius:14px; background:var(--bg,#fff); color:var(--ink)}
.lc-err{color:var(--red,#d33); font-size:12px; margin-right:auto}
.lc-group{margin-bottom:10px}
.lc-head{display:flex; align-items:center; gap:8px; margin-bottom:4px}
.lc-head i{font-style:normal; font-size:11px; color:var(--ink2)}
.lc-line{font-family:ui-monospace,Menlo,monospace; font-size:12px; padding:3px 0;
  color:var(--ink); word-break:break-all}
.lc-bad{color:var(--red)}
.lc-line .pill{float:right}
.lc-act{float:right; display:inline-flex; gap:6px; margin-left:8px}
.lc-act button{font-size:11px; padding:2px 8px; border:1px solid var(--ink3,#ccc);
  border-radius:10px; background:var(--bg,#fff); color:var(--ink)}
.lc-danger{color:var(--red,#d33); border-color:var(--red,#d33)}
.lc-addbar{margin-top:6px}
.lc-addbar > button{font-size:12px; padding:4px 12px; border:1px dashed var(--ink3,#ccc);
  border-radius:12px; background:transparent; color:var(--ink2)}
.lc-form{display:flex; gap:6px; flex-wrap:wrap; align-items:center}
.lc-form input{flex:1; min-width:150px; font-size:12px; padding:5px 8px;
  border:1px solid var(--ink3,#ccc); border-radius:8px; background:var(--bg,#fff); color:var(--ink)}
.lc-form button{font-size:12px; padding:5px 12px; border:1px solid var(--ink3,#ccc);
  border-radius:8px; background:var(--bg,#fff); color:var(--ink)}
.lc-formerr{width:100%}
</style>
