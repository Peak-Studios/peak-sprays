import type {
  FreehandLayer,
  GraffitiComposition,
  GraffitiLayer,
  ImageLayer,
  StencilLayer,
  TextLayer,
  WorldEraseStroke,
} from '../types/graffiti.ts'
import { drawTexturedStroke, normalizeColor } from './brushes.ts'
import { drawTextLayer, ensureFontsLoaded } from './text.ts'
import { getProcessedImageCanvas } from './images.ts'
import { STENCILS } from './stencils.ts'

class ScratchCanvasPool {
  private pool: HTMLCanvasElement[] = []
  private maxCapacity = 8

  acquire(width: number, height: number): HTMLCanvasElement {
    let canvas = this.pool.pop()
    if (!canvas) {
      canvas = document.createElement('canvas')
    }
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width
      canvas.height = height
    }
    const ctx = canvas.getContext('2d')
    if (ctx) {
      ctx.clearRect(0, 0, width, height)
    }
    return canvas
  }

  release(canvas: HTMLCanvasElement) {
    if (this.pool.length < this.maxCapacity) {
      this.pool.push(canvas)
    }
  }
}

const scratchPool = new ScratchCanvasPool()

export interface RenderOptions {
  clear?: boolean
  scale?: number
  generationToken?: number
  isDui?: boolean
}

let activeGenerationToken = 0

export function getNextGenerationToken(): number {
  return ++activeGenerationToken
}

export function cancelPendingRenders(): void {
  ++activeGenerationToken
}

/**
 * Draws a stencil stamp layer deterministically.
 */
function drawStencilLayer(
  ctx: CanvasRenderingContext2D,
  layer: StencilLayer
): void {
  const points = STENCILS[layer.stencilId] || STENCILS.Peak
  if (!points || points.length === 0) return

  const size = Math.max(5, layer.size || 50)
  const color = normalizeColor(layer.color, '#D6FF62')

  ctx.save()
  ctx.translate(layer.x, layer.y)
  if (layer.rotation) {
    ctx.rotate((layer.rotation * Math.PI) / 180)
  }
  const scale = size / 20.0
  ctx.scale(scale, scale)

  ctx.fillStyle = color
  ctx.beginPath()
  ctx.moveTo(points[0].x, points[0].y)
  for (let i = 1; i < points.length; i++) {
    ctx.lineTo(points[i].x, points[i].y)
  }
  ctx.closePath()
  ctx.fill()

  ctx.restore()
}

/**
 * Composites world cleaning strokes using destination-out.
 */
function applyWorldEraseMask(
  ctx: CanvasRenderingContext2D,
  eraseMask: WorldEraseStroke[]
): void {
  if (!eraseMask || eraseMask.length === 0) return

  ctx.save()
  ctx.globalCompositeOperation = 'destination-out'

  for (const stroke of eraseMask) {
    const points = stroke.points
    if (!points || points.length === 0) continue

    const size = Math.max(4, stroke.size || 15)
    ctx.lineWidth = size
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'

    ctx.beginPath()
    ctx.moveTo(points[0].x, points[0].y)
    for (let p = 1; p < points.length; p++) {
      ctx.lineTo(points[p].x, points[p].y)
    }
    ctx.stroke()
  }

  ctx.restore()
}

/**
 * Renders an entire composition document deterministically into an isolated private working surface,
 * committing to the destination canvas ONLY if the render generation is still current.
 */
export async function renderComposition(
  destCtx: CanvasRenderingContext2D,
  composition: GraffitiComposition,
  options: RenderOptions = {}
): Promise<boolean> {
  const token = options.generationToken || ++activeGenerationToken

  const width = composition.width || 1024
  const height = composition.height || 1024

  // 1. Pre-load all text fonts
  const customFonts: string[] = []
  if (composition.layers) {
    for (const layer of composition.layers) {
      if (layer.type === 'text' && (layer as TextLayer).font) {
        customFonts.push((layer as TextLayer).font)
      }
    }
  }
  if (customFonts.length > 0) {
    await ensureFontsLoaded(customFonts)
  }

  // Check staleness after font loading async boundary
  if (token < activeGenerationToken) {
    return false
  }

  // 2. Pre-process any image layers before allocating rendering scratch
  const imageCanvasMap = new Map<string, HTMLCanvasElement | null>()
  const layers = composition.layers || []

  for (const layer of layers) {
    if (layer.visible === false) continue
    if (layer.type === 'image') {
      const imgLayer = layer as ImageLayer
      const sourceUrl =
        (imgLayer as any).sourceType === 'raster' && (imgLayer as any).data
          ? `data:image/${(imgLayer as any).format || 'png'};base64,${(imgLayer as any).data}`
          : imgLayer.dataUrl || imgLayer.url

      if (sourceUrl) {
        const processed = await getProcessedImageCanvas(
          sourceUrl,
          imgLayer.filters,
          imgLayer.width || 256,
          imgLayer.height || 256
        )
        // Check staleness after image processing async boundary
        if (token < activeGenerationToken) {
          return false
        }
        imageCanvasMap.set(layer.id, processed)
      }
    }
  }

  // 3. Render complete frame into private working surface
  const workingCanvas = scratchPool.acquire(width, height)
  const workingCtx = workingCanvas.getContext('2d')
  if (!workingCtx) {
    scratchPool.release(workingCanvas)
    return false
  }

  const layerScratch = scratchPool.acquire(width, height)
  const layerScratchCtx = layerScratch.getContext('2d')
  if (!layerScratchCtx) {
    scratchPool.release(workingCanvas)
    scratchPool.release(layerScratch)
    return false
  }

  try {
    for (let l = 0; l < layers.length; l++) {
      const layer = layers[l]
      if (layer.visible === false) continue

      // Clear scratch for this layer
      layerScratchCtx.clearRect(0, 0, width, height)

      // STABLE APPEARANCE SEED: Derived purely from layer ID, NOT stack index l!
      const layerSeedKey = layer.id || `layer_${layer.name || 'unnamed'}`

      if (layer.type === 'freehand') {
        const fh = layer as FreehandLayer
        if (fh.strokes) {
          for (let s = 0; s < fh.strokes.length; s++) {
            const stroke = fh.strokes[s]
            if (stroke.type === 'erase') {
              layerScratchCtx.save()
              layerScratchCtx.globalCompositeOperation = 'destination-out'
              const pts = stroke.points
              if (pts && pts.length > 0) {
                layerScratchCtx.lineWidth = stroke.size || 20
                layerScratchCtx.lineCap = 'round'
                layerScratchCtx.lineJoin = 'round'
                layerScratchCtx.beginPath()
                layerScratchCtx.moveTo(pts[0].x, pts[0].y)
                for (let p = 1; p < pts.length; p++) {
                  layerScratchCtx.lineTo(pts[p].x, pts[p].y)
                }
                layerScratchCtx.stroke()
              }
              layerScratchCtx.restore()
            } else {
              drawTexturedStroke(layerScratchCtx, stroke, `${layerSeedKey}_s${s}`)
            }
          }
        }
      } else if (layer.type === 'text') {
        drawTextLayer(layerScratchCtx, layer as TextLayer, layerSeedKey)
      } else if (layer.type === 'stencil') {
        drawStencilLayer(layerScratchCtx, layer as StencilLayer)
      } else if (layer.type === 'image') {
        const imgLayer = layer as ImageLayer
        const processed = imageCanvasMap.get(layer.id)
        if (processed) {
          layerScratchCtx.save()
          layerScratchCtx.translate(imgLayer.x, imgLayer.y)
          if (imgLayer.rotation) {
            layerScratchCtx.rotate((imgLayer.rotation * Math.PI) / 180)
          }
          layerScratchCtx.scale(imgLayer.flipX ? -1 : 1, imgLayer.flipY ? -1 : 1)
          layerScratchCtx.drawImage(
            processed,
            -(imgLayer.width || 256) / 2,
            -(imgLayer.height || 256) / 2
          )
          layerScratchCtx.restore()
        }
      }

      // Composite layer scratch onto working surface with layer opacity applied once!
      workingCtx.save()
      workingCtx.globalAlpha = typeof layer.opacity === 'number' ? layer.opacity : 1.0
      workingCtx.drawImage(layerScratch, 0, 0)
      workingCtx.restore()
    }

    // Composite independent world-cleaning erase mask over assembled artwork
    if (composition.eraseMask && composition.eraseMask.length > 0) {
      applyWorldEraseMask(workingCtx, composition.eraseMask)
    }

    // 4. Atomic commit: check if generation is still current before touching destCtx
    if (token < activeGenerationToken) {
      return false
    }

    if (options.clear !== false) {
      destCtx.clearRect(0, 0, destCtx.canvas.width, destCtx.canvas.height)
    }

    destCtx.save()
    if (options.scale && options.scale !== 1.0) {
      destCtx.scale(options.scale, options.scale)
    }
    destCtx.drawImage(workingCanvas, 0, 0)
    destCtx.restore()

    return true
  } finally {
    scratchPool.release(workingCanvas)
    scratchPool.release(layerScratch)
  }
}
