import { createApp, computed, defineComponent, h, reactive } from 'vue'
import './sceneDui.css'
import type { SceneData } from '@/store/sceneState'

const imageBackgrounds = new Set(['sticky', 'oldPaper', 'oldPaper2', 'oldPaper3', 'tornPaper', 'warning', 'wood', 'water', 'blood', 'blueprint'])

const state = reactive({
  visible: false,
  isEye: false,
  sceneData: null as SceneData | null,
})

const rendererName = new URLSearchParams(window.location.search).get('renderer') || 'unknown'

function nuiResourceName() {
  return (window as any).GetParentResourceName ? (window as any).GetParentResourceName() : 'peak-sprays'
}

function notifyReady(attempt = 0) {
  fetch(`https://${nuiResourceName()}/sceneDui:ready`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ renderer: rendererName }),
  }).catch(() => {
    if (attempt < 20) window.setTimeout(() => notifyReady(attempt + 1), 250)
  })
}

function onMessage(event: MessageEvent) {
  let data = event.data
  if (typeof data === 'string') {
    try { data = JSON.parse(data) } catch { return }
  }
  if (!data?.action) return

  if (data.action === 'setSceneData') {
    state.sceneData = data.payload
    state.visible = Boolean(data.payload)
  }
  if (data.action === 'setVisible') state.visible = typeof data.payload === 'object' ? Boolean(data.payload?.visible) : Boolean(data.payload)
  if (data.action === 'setEye') state.isEye = Boolean(data.payload)
}

const SceneText = {
  setup() {
    return () => {
      const data = state.sceneData
      return h('div', { class: ['scene-text', data?.fontOutline, data?.fontStyle] }, data?.text || '')
    }
  },
}

const App = defineComponent({
  setup() {
    const textStyle = computed(() => {
      const data = state.sceneData
      return {
        '--col': data?.fontColor || '#fff',
        '--shadowCol': data?.fontOutlineColor || '#000',
        '--size': `${data?.fontSize || 48}px`,
        '--font': `"${data?.font || 'Oswald'}", Arial, sans-serif`,
      }
    })

    const backgroundStyle = computed(() => {
      const data = state.sceneData
      return {
        '--bg': data?.backgroundColor || '#262626',
        '--sizeX': `${data?.backgroundSizeX || 100}%`,
        '--sizeY': `${data?.backgroundSizeY || 100}%`,
        '--offsetX': `${data?.backgroundOffsetX || 50}%`,
        '--offsetY': `${data?.backgroundOffsetY || 50}%`,
      }
    })

    return () => {
      if (!state.visible || !state.sceneData) return null
      if (state.isEye) {
        return h('div', { class: 'scene-dui eye-wrap' }, [h('div', { class: 'eye' }, 'VIEW')])
      }

      const data = state.sceneData
      const isImage = imageBackgrounds.has(data.background)
      const hasSolidBackground = data.background !== 'empty' && !isImage
      return h('div', { class: 'scene-dui' }, [
        h('div', {
          class: ['texture', data.background, isImage ? 'image-bg' : hasSolidBackground ? 'solid' : 'transparent-bg', data.backgroundFill],
          style: backgroundStyle.value,
        }, [
          isImage ? h('img', { src: `scene-assets/backgrounds/${data.background}.png`, alt: '' }) : null,
          h(SceneText, { style: textStyle.value }),
        ]),
      ])
    }
  },
})

window.addEventListener('message', onMessage)
createApp(App).mount('#scene-app')
notifyReady()
