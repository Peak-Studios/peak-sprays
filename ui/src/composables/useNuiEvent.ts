import { onMounted, onUnmounted } from 'vue'

type NuiMessageHandler = (data: Record<string, unknown>) => void

export function useNuiEvent(action: string, handler: NuiMessageHandler) {
  const listener = (event: MessageEvent) => {
    let data = event.data
    if (typeof data === 'string') {
      try { data = JSON.parse(data) } catch { return }
    }
    if (data && data.action === action) {
      handler(data)
    }
  }

  onMounted(() => window.addEventListener('message', listener))
  onUnmounted(() => window.removeEventListener('message', listener))
}
