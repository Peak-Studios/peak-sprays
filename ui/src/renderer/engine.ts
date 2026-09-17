import type {
  FreehandLayer,
  GraffitiComposition,
  GraffitiLayer,
  ImageLayer,
  StencilLayer,
  TextLayer,
  WorldEraseStroke,
} from '@/types/graffiti'
import { drawTexturedStroke, normalizeColor } from './brushes'
import { drawTextLayer, ensureFontsLoaded } from './text'
import { getProcessedImageCanvas } from './images'
import { STENCILS } from './stencils'

let pooledScratchCanvas: HTMLCanvasElement | null = null

function getScratchCanvas(width: number, height: number): HTMLCanvasElement {
  if (!pooledScratchCanvas) {
    pooledScratchCanvas = document.createElement('canvas')
  }
  if (pooledScratchCanvas.width !== width || pooledScratchCanvas.height !== height) {
    pooledScratchCanvas.width = width
    pooledScratchCanvas.height = height
  }
  const sctx = pooledScratchCanvas.getContext('2d')
  if (sctx) {
    sctx.clearRect(0, 0, width, height)
  }
  return pooledScratchCanvas
}

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
 * Renders an entire composition document onto the destination 2D context.
 * Guarantees 100% WYSIWYG matching between editor and in-world DUI.
 */
export async function renderComposition(
  destCtx: CanvasRenderingContext2D,
  composition: GraffitiComposition,
  options: RenderOptions = {}
): Promise<boolean> {
  const token = options.generationToken || ++activeGenerationToken

  const width = composition.width || 1024
  const height = composition.height || 1024

  // Pre-load all text fonts
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

  // If a newer generation started while waiting for fonts, abort this pass!
  if (options.generationToken && options.generationToken < activeGenerationToken) {
    return false
  }

  if (options.clear !== false) {
    destCtx.clearRect(0, 0, destCtx.canvas.width, destCtx.canvas.height)
  }

  destCtx.save()
  if (options.scale && options.scale !== 1.0) {
    destCtx.scale(options.scale, options.scale)
  }

  const scratch = getScratchCanvas(width, height)
  const scratchCtx = scratch.getContext('2d')
  if (!scratchCtx) {
    destCtx.restore()
    return false
  }

  const layers = composition.layers || []
  for (let l = 0; l < layers.length; l++) {
    const layer = layers[l]
    if (layer.visible === false) continue

    // Clear scratch surface for this layer
    scratchCtx.clearRect(0, 0, width, height)

    // Render layer content into scratch surface at full internal opacity
    const layerSeedKey = `${layer.id}_${l}`

    if (layer.type === 'freehand') {
      const fh = layer as FreehandLayer
      if (fh.strokes) {
        for (let s = 0; s < fh.strokes.length; s++) {
          const stroke = fh.strokes[s]
          if (stroke.type === 'erase') {
            scratchCtx.save()
            scratchCtx.globalCompositeOperation = 'destination-out'
            const pts = stroke.points
            if (pts && pts.length > 0) {
              scratchCtx.lineWidth = stroke.size || 20
              scratchCtx.lineCap = 'round'
              scratchCtx.lineJoin = 'round'
              scratchCtx.beginPath()
              scratchCtx.moveTo(pts[0].x, pts[0].y)
              for (let p = 1; p < pts.length; p++) {
                scratchCtx.lineTo(pts[p].x, pts[p].y)
              }
              scratchCtx.stroke()
            }
            scratchCtx.restore()
          } else {
            drawTexturedStroke(scratchCtx, stroke, `${layerSeedKey}_s${s}`)
          }
        }
      }
    } else if (layer.type === 'text') {
      drawTextLayer(scratchCtx, layer as TextLayer, layerSeedKey)
    } else if (layer.type === 'stencil') {
      drawStencilLayer(scratchCtx, layer as StencilLayer)
    } else if (layer.type === 'image') {
      const imgLayer = layer as ImageLayer
      const sourceUrl = imgLayer.dataUrl || imgLayer.url
      if (sourceUrl) {
        const processed = await getProcessedImageCanvas(
          sourceUrl,
          imgLayer.filters,
          imgLayer.width || 256,
          imgLayer.height || 256
        )
        if (processed) {
          scratchCtx.save()
          scratchCtx.translate(imgLayer.x, imgLayer.y)
          if (imgLayer.rotation) {
            scratchCtx.rotate((imgLayer.rotation * Math.PI) / 180)
          }
          scratchCtx.scale(imgLayer.flipX ? -1 : 1, imgLayer.flipY ? -1 : 1)
          scratchCtx.drawImage(
            processed,
            -(imgLayer.width || 256) / 2,
            -(imgLayer.height || 256) / 2
          )
          scratchCtx.restore()
        }
      }
    }

    // Composite scratch canvas to destination with layer opacity applied once!
    destCtx.save()
    destCtx.globalAlpha = typeof layer.opacity === 'number' ? layer.opacity : 1.0
    destCtx.drawImage(scratch, 0, 0)
    destCtx.restore()
  }

  // Composite independent world-cleaning erase mask over the assembled artwork!
  if (composition.eraseMask && composition.eraseMask.length > 0) {
    applyWorldEraseMask(destCtx, composition.eraseMask)
  }

  destCtx.restore()
  return true
}
