import {
  createDuiReducerState,
  reduceDuiMessage,
  type DuiReducerState,
} from './renderer/duiProtocol.ts'
import {
  drawTexturedStroke,
  renderComposition,
  getNextGenerationToken,
  type RenderOptions,
} from './renderer'

// Declare window message interface for FiveM DUI
declare global {
  interface Window {
    GetParentResourceName?: () => string
    __PEAK_CANVAS__?: any
  }
}

const canvas = document.getElementById('sprayCanvas') as HTMLCanvasElement
const ctx = canvas?.getContext('2d', { willReadFrequently: false })

const duiState: DuiReducerState = createDuiReducerState(1024, 1024)
let renderToken = 0

function resizeCanvas(width: number, height: number) {
  if (canvas) {
    canvas.width = width
    canvas.height = height
  }
}

async function renderCurrentState() {
  if (!ctx || !duiState.composition) return
  renderToken++
  const options: RenderOptions = {
    clear: true,
    generationToken: renderToken,
    isDui: true,
  }
  await renderComposition(ctx, duiState.composition, options)
}

// FiveM SendDuiMessage listener
window.addEventListener('message', async (event) => {
  const data = event.data
  if (!data || typeof data !== 'object') return

  const result = reduceDuiMessage(duiState, data)

  if (result.canvasResized) {
    resizeCanvas(result.canvasResized.width, result.canvasResized.height)
  }

  if (result.liveStrokeSegment && ctx) {
    const { stroke, isErase, points } = result.liveStrokeSegment
    if (isErase) {
      ctx.save()
      ctx.globalCompositeOperation = 'destination-out'
      ctx.lineWidth = Math.max(1, stroke.size || 14)
      ctx.lineCap = 'round'
      ctx.lineJoin = 'round'
      ctx.beginPath()
      ctx.moveTo(points[0].x, points[0].y)
      if (points.length > 1) {
        ctx.lineTo(points[points.length - 1].x, points[points.length - 1].y)
      } else {
        ctx.lineTo(points[0].x + 0.1, points[0].y + 0.1)
      }
      ctx.stroke()
      ctx.restore()
    } else {
      drawTexturedStroke(
        ctx,
        { ...stroke, points },
        `live_seg_${Date.now()}_${points.length}`
      )
    }
  }

  if (result.needsFullRedraw) {
    await renderCurrentState()
  }
})

if (typeof window !== 'undefined') {
  window.__PEAK_CANVAS__ = {
    canvas,
    ctx,
    duiState,
    renderCurrentState,
    renderComposition,
    getNextGenerationToken,
  }
}
