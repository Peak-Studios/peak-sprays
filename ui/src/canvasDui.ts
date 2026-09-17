import type {
  FreehandStroke,
  GraffitiComposition,
} from '@/types/graffiti'
import {
  drawTexturedStroke,
  renderComposition,
  normalizeColor,
  type RenderOptions,
} from '@/renderer'

// Declare window message interface for FiveM DUI
declare global {
  interface Window {
    GetParentResourceName?: () => string
  }
}

const canvas = document.getElementById('sprayCanvas') as HTMLCanvasElement
const ctx = canvas?.getContext('2d', { willReadFrequently: false })

let canvasW = 1024
let canvasH = 1024
let currentComposition: GraffitiComposition | null = null
let currentStroke: FreehandStroke | null = null
let renderToken = 0

function resizeCanvas(width: number, height: number) {
  canvasW = width
  canvasH = height
  if (canvas) {
    canvas.width = width
    canvas.height = height
  }
}

async function renderCurrentState() {
  if (!ctx || !currentComposition) return
  renderToken++
  const options: RenderOptions = {
    clear: true,
    generationToken: renderToken,
    isDui: true,
  }
  await renderComposition(ctx, currentComposition, options)
}

function normalizeIncomingStrokes(data: any): GraffitiComposition {
  if (!data) {
    return {
      version: '1.0.0',
      title: 'DUI Canvas',
      width: canvasW,
      height: canvasH,
      background: 'transparent',
      layers: [],
    }
  }

  // Already a normalized document with composition
  if (data.documentType === 'layered' || data.isComposition === true || data.composition) {
    const comp = data.composition || data
    return {
      version: comp.version || '1.0.0',
      title: comp.title || 'Spray',
      width: comp.width || canvasW,
      height: comp.height || canvasH,
      background: comp.background || 'transparent',
      layers: comp.layers || [],
      eraseMask: data.eraseMask || comp.eraseMask || [],
    }
  }

  // Legacy stroke array
  if (Array.isArray(data)) {
    return {
      version: '1.0.0',
      title: 'Legacy Painting',
      width: canvasW,
      height: canvasH,
      background: 'transparent',
      layers: [
        {
          id: 'legacy_layer_1',
          name: 'Legacy Artwork',
          type: 'freehand',
          visible: true,
          locked: false,
          opacity: 1.0,
          strokes: data,
        },
      ],
      eraseMask: [],
    }
  }

  return {
    version: '1.0.0',
    title: 'DUI Painting',
    width: canvasW,
    height: canvasH,
    background: 'transparent',
    layers: [],
  }
}

// FiveM SendDuiMessage listener
window.addEventListener('message', async (event) => {
  const data = event.data
  if (!data || typeof data !== 'object') return

  switch (data.action) {
    case 'init': {
      const w = Number(data.width) || 1024
      const h = Number(data.height) || 1024
      resizeCanvas(w, h)
      break
    }

    case 'loadPaintingDocument': {
      currentComposition = normalizeIncomingStrokes(data.document || data.strokes)
      if (currentComposition.width && currentComposition.height) {
        resizeCanvas(currentComposition.width, currentComposition.height)
      }
      await renderCurrentState()
      break
    }

    case 'loadStrokes': {
      currentComposition = normalizeIncomingStrokes(data.strokes)
      if (currentComposition.width && currentComposition.height) {
        resizeCanvas(currentComposition.width, currentComposition.height)
      }
      await renderCurrentState()
      break
    }

    case 'startStroke': {
      currentStroke = {
        type: data.type === 'erase' ? 'erase' : 'paint',
        style: data.style || 'spray',
        color: normalizeColor(data.color, '#D6FF62'),
        size: Math.max(1, Number(data.size) || 14),
        density: Number(data.density) || 25,
        pressure: Number(data.pressure) || 0.85,
        scatter: Number(data.scatter) || 1.0,
        points: [{ x: Number(data.x) || 0, y: Number(data.y) || 0, pressure: Number(data.pressure) || 0.85 }],
      }
      if (ctx && currentStroke) {
        drawTexturedStroke(ctx, currentStroke, `live_${Date.now()}`)
      }
      break
    }

    case 'addPoint': {
      if (currentStroke && ctx) {
        const pt = { x: Number(data.x) || 0, y: Number(data.y) || 0, pressure: Number(data.pressure) || 0.85 }
        currentStroke.points.push(pt)
        // Draw segment immediately for interactive smoothness
        drawTexturedStroke(ctx, { ...currentStroke, points: [currentStroke.points[currentStroke.points.length - 2] || pt, pt] }, `live_pt_${currentStroke.points.length}`)
      }
      break
    }

    case 'drawStroke': {
      if (ctx && data.stroke) {
        drawTexturedStroke(ctx, data.stroke, `draw_${Date.now()}`)
      }
      break
    }

    case 'clear': {
      if (ctx) {
        ctx.clearRect(0, 0, canvasW, canvasH)
      }
      currentComposition = null
      currentStroke = null
      break
    }
  }
})
