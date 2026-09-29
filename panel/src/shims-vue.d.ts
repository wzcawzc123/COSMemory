declare module '*.vue' {
  import type { DefineComponent } from 'vue'
  const comp: DefineComponent<{}, {}, any>
  export default comp
}
