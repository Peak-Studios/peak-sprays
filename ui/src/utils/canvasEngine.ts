import type {
  BrushStyleId,
  FreehandStroke,
  GraffitiComposition,
  GraffitiLayer,
  ImageLayer,
  StrokePoint,
  TextLayer,
  StencilLayer,
  FreehandLayer,
} from '@/types/graffiti'

export const STENCILS: Record<string, { x: number; y: number }[]> = {
  Peak: [
    { x: 0, y: -10 },
    { x: 10, y: 10 },
    { x: -10, y: 10 },
    { x: 0, y: -10 },
  ],
  Star: [
    { x: 0, y: -15 },
    { x: 4, y: -5 },
    { x: 15, y: -5 },
    { x: 7, y: 2 },
    { x: 10, y: 12 },
    { x: 0, y: 5 },
    { x: -10, y: 12 },
    { x: -7, y: 2 },
    { x: -15, y: -5 },
    { x: -4, y: -5 },
    { x: 0, y: -15 },
  ],
  Crown: [
    { x: -10, y: 5 },
    { x: -10, y: -5 },
    { x: -5, y: 0 },
    { x: 0, y: -10 },
    { x: 5, y: 0 },
    { x: 10, y: -5 },
    { x: 10, y: 5 },
    { x: -10, y: 5 },
  ],
  Skull: [
    { x: -5, y: -8 },
    { x: 5, y: -8 },
    { x: 8, y: -3 },
    { x: 8, y: 3 },
    { x: 4, y: 10 },
    { x: 2, y: 10 },
    { x: 2, y: 6 },
    { x: -2, y: 6 },
    { x: -2, y: 10 },
    { x: -4, y: 10 },
    { x: -8, y: 3 },
    { x: -8, y: -3 },
    { x: -5, y: -8 },
  ],
  Heart: [
    { x: 0, y: 10 },
    { x: -10, y: 0 },
    { x: -10, y: -5 },
    { x: -5, y: -10 },
    { x: 0, y: -5 },
    { x: 5, y: -10 },
    { x: 10, y: -5 },
    { x: 10, y: 0 },
    { x: 0, y: 10 },
  ],
  Anarchy: [
    { x: 0, y: -14 },
    { x: 10, y: 14 },
    { x: 3, y: 2 },
    { x: -3, y: 2 },
    { x: -10, y: 14 },
    { x: 0, y: -14 },
  ],
  Biohazard: [
    { x: 0, y: -12 },
    { x: 8, y: -4 },
    { x: 12, y: 6 },
    { x: 0, y: 14 },
    { x: -12, y: 6 },
    { x: -8, y: -4 },
    { x: 0, y: -12 },
  ],
}

export function clamp(v: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, v))
}

export function normalizeColor(color?: string, fallback = '#000000'): string {
  if (!color || typeof color !== 'string') return fallback
  let hex = color.trim().replace(/[^a-fA-F0-9]/g, '')
  if (hex.length === 3) {
    hex = hex.split('').map((c) => c + c).join('')
  } else if (hex.length >= 6) {
    hex = hex.slice(0, 6)
  } else {
    return fallback
  }
  return `#${hex.toUpperCase()}`
}

export function hexToRgb(color: string): { r: number; g: number; b: number } {
  const hex = normalizeColor(color)
  return {
    r: parseInt(hex.slice(1, 3), 16) || 0,
    g: parseInt(hex.slice(3, 5), 16) || 0,
    b: parseInt(hex.slice(5, 7), 16) || 0,
  }
}

// ─── Image Cache ───────────────────────────────────────────────────────
const imageBitmapCache = new Map<string, Promise<HTMLImageElement>>()

export function loadCanvasImage(url: string): Promise<HTMLImageElement> {
  if (imageBitmapCache.has(url)) {
    return imageBitmapCache.get(url)!
  }
  const promise = new Promise<HTMLImageElement>((resolve, reject) => {
    const img = new Image()
    img.crossOrigin = 'anonymous'
    img.onload = () => resolve(img)
    img.onerror = () => reject(new Error('Image failed to load: ' + url))
    img.src = url
  })
  imageBitmapCache.set(url, promise)
  return promise
}

// ─── Textured Brush Implementations ────────────────────────────────────

export function drawDot(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  size: number,
  color: string,
  pressure = 0.8
) {
  ctx.save()
  ctx.globalAlpha = clamp(0.9 * pressure + 0.1, 0, 1)
  ctx.fillStyle = normalizeColor(color)
  ctx.beginPath()
  ctx.arc(x, y, Math.max(0.5, size * 0.5), 0, 2 * Math.PI)
  ctx.fill()
  ctx.restore()
}

export function drawSoftDot(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  size: number,
  color: string,
  pressure = 0.8,
  softness = 0.55
) {
  const radius = Math.max(1, size * 0.5)
  const rgb = hexToRgb(color)
  const alpha = clamp(pressure * 0.55, 0.04, 0.9)
  const gradient = ctx.createRadialGradient(x, y, 0, x, y, radius)
  gradient.addColorStop(0, `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${alpha})`)
  gradient.addColorStop(clamp(softness, 0.15, 0.9), `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${alpha * 0.35})`)
  gradient.addColorStop(1, `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, 0)`)

  ctx.save()
  ctx.fillStyle = gradient
  ctx.beginPath()
  ctx.arc(x, y, radius, 0, 2 * Math.PI)
  ctx.fill()
  ctx.restore()
}

export function drawLine(
  ctx: CanvasRenderingContext2D,
  x1: number,
  y1: number,
  x2: number,
  y2: number,
  size: number,
  color: string,
  pressure = 0.8
) {
  ctx.save()
  ctx.globalAlpha = clamp(0.9 * pressure + 0.1, 0, 1)
  ctx.strokeStyle = normalizeColor(color)
  ctx.lineWidth = Math.max(0.75, size)
  ctx.lineCap = 'round'
  ctx.lineJoin = 'round'
  ctx.beginPath()
  ctx.moveTo(x1, y1)
  ctx.lineTo(x2, y2)
  ctx.stroke()
  ctx.restore()
}

export function drawScatter(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  radius: number,
  count: number,
  color: string,
  pressure = 0.8,
  minDot = 0.5,
  maxDot = 2.0
) {
  if (count <= 0) return
  const rgb = hexToRgb(color)
  const spread = Math.max(0.5, radius)
  for (let i = 0; i < count; i++) {
    const u1 = Math.random()
    const u2 = Math.random()
    const mag = Math.sqrt(-2 * Math.log(u1 + 1e-4))
    const px = cx + mag * Math.cos(2 * Math.PI * u2) * spread * 0.45
    const py = cy + mag * Math.sin(2 * Math.PI * u2) * spread * 0.45
    const dotR = minDot + (maxDot - minDot) * Math.random()
    const alpha = clamp(pressure * (0.25 + 0.65 * Math.random()), 0, 1)
    ctx.beginPath()
    ctx.arc(px, py, dotR, 0, 2 * Math.PI)
    ctx.fillStyle = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${alpha})`
    ctx.fill()
  }
}

/**
 * Sidewalk Chalk Brush: dry, porous, fractured grain
 */
export function drawChalkSegment(
  ctx: CanvasRenderingContext2D,
  p1: StrokePoint,
  p2: StrokePoint,
  size: number,
  color: string,
  pressure = 0.8
) {
  const segLen = Math.hypot(p2.x - p1.x, p2.y - p1.y)
  const steps = Math.max(1, Math.ceil(segLen / Math.max(1.5, size * 0.2)))
  const rgb = hexToRgb(color)

  for (let i = 0; i <= steps; i++) {
    const t = i / steps
    const cx = p1.x + (p2.x - p1.x) * t
    const cy = p1.y + (p2.y - p1.y) * t
    const grainCount = Math.max(3, Math.floor(size * 0.75 * pressure))

    for (let g = 0; g < grainCount; g++) {
      const angle = Math.random() * Math.PI * 2
      const dist = (Math.random() ** 0.5) * (size * 0.48)
      const gx = cx + Math.cos(angle) * dist + (Math.random() - 0.5) * 1.5
      const gy = cy + Math.sin(angle) * dist + (Math.random() - 0.5) * 1.5
      const alpha = (0.25 + Math.random() * 0.55) * pressure
      const r = 0.8 + Math.random() * 1.8

      ctx.fillStyle = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${alpha})`
      ctx.fillRect(gx - r * 0.5, gy - r * 0.5, r, r)
    }
  }
}

/**
 * Street Crayon Brush: waxy, thick core with rough paper tooth borders
 */
export function drawCrayonSegment(
  ctx: CanvasRenderingContext2D,
  p1: StrokePoint,
  p2: StrokePoint,
  size: number,
  color: string,
  pressure = 0.8
) {
  const rgb = hexToRgb(color)
  // Waxy semi-transparent core
  ctx.save()
  ctx.strokeStyle = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${clamp(pressure * 0.75, 0.2, 0.95)})`
  ctx.lineWidth = Math.max(2, size * 0.7)
  ctx.lineCap = 'square'
  ctx.beginPath()
  ctx.moveTo(p1.x, p1.y)
  ctx.lineTo(p2.x, p2.y)
  ctx.stroke()
  ctx.restore()

  // Textured border flecks
  const segLen = Math.hypot(p2.x - p1.x, p2.y - p1.y)
  const steps = Math.max(1, Math.ceil(segLen / Math.max(2, size * 0.25)))
  for (let i = 0; i <= steps; i++) {
    const t = i / steps
    const cx = p1.x + (p2.x - p1.x) * t
    const cy = p1.y + (p2.y - p1.y) * t
    const fleckCount = Math.max(2, Math.floor(size * 0.4))
    for (let f = 0; f < fleckCount; f++) {
      const offset = (Math.random() - 0.5) * size * 1.1
      ctx.fillStyle = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${Math.random() * 0.65 * pressure})`
      ctx.fillRect(cx + offset, cy + (Math.random() - 0.5) * size * 0.5, 1.4, 1.4)
    }
  }
}

/**
 * Marker Bleed Brush: wet ink chisel with micro-feathering
 */
export function drawMarkerBleedSegment(
  ctx: CanvasRenderingContext2D,
  p1: StrokePoint,
  p2: StrokePoint,
  size: number,
  color: string,
  pressure = 0.8
) {
  const rgb = hexToRgb(color)
  // Main wet line
  ctx.save()
  ctx.strokeStyle = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${clamp(pressure * 0.92, 0.4, 1)})`
  ctx.lineWidth = size
  ctx.lineCap = 'round'
  ctx.beginPath()
  ctx.moveTo(p1.x, p1.y)
  ctx.lineTo(p2.x, p2.y)
  ctx.stroke()
  ctx.restore()

  // Capillary bleed dots outside edge
  const segLen = Math.hypot(p2.x - p1.x, p2.y - p1.y)
  const bleedSteps = Math.max(1, Math.ceil(segLen / Math.max(3, size * 0.3)))
  for (let i = 0; i <= bleedSteps; i++) {
    const t = i / bleedSteps
    const cx = p1.x + (p2.x - p1.x) * t
    const cy = p1.y + (p2.y - p1.y) * t
    if (Math.random() < 0.45) {
      const angle = Math.random() * Math.PI * 2
      const dist = (size * 0.45) + Math.random() * (size * 0.35)
      drawSoftDot(ctx, cx + Math.cos(angle) * dist, cy + Math.sin(angle) * dist, size * 0.3, color, pressure * 0.35, 0.8)
    }
  }
}

/**
 * Paint Roller Brush: wide flat band with parallel texture stripes
 */
export function drawRollerSegment(
  ctx: CanvasRenderingContext2D,
  p1: StrokePoint,
  p2: StrokePoint,
  size: number,
  color: string,
  pressure = 0.8
) {
  const rgb = hexToRgb(color)
  const rollerWidth = Math.max(16, size * 2.5)
  const angle = Math.atan2(p2.y - p1.y, p2.x - p1.x) + Math.PI / 2

  // Base roller stroke
  ctx.save()
  ctx.strokeStyle = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${clamp(pressure * 0.85, 0.2, 0.95)})`
  ctx.lineWidth = rollerWidth
  ctx.lineCap = 'butt'
  ctx.beginPath()
  ctx.moveTo(p1.x, p1.y)
  ctx.lineTo(p2.x, p2.y)
  ctx.stroke()

  // Roller edge ridges (darker outer tracks)
  const rX = Math.cos(angle) * (rollerWidth * 0.48)
  const rY = Math.sin(angle) * (rollerWidth * 0.48)
  ctx.strokeStyle = `rgba(${Math.max(0, rgb.r - 25)}, ${Math.max(0, rgb.g - 25)}, ${Math.max(0, rgb.b - 25)}, 0.45)`
  ctx.lineWidth = Math.max(1, size * 0.2)
  ctx.beginPath()
  ctx.moveTo(p1.x + rX, p1.y + rY)
  ctx.lineTo(p2.x + rX, p2.y + rY)
  ctx.moveTo(p1.x - rX, p1.y - rY)
  ctx.lineTo(p2.x - rX, p2.y - rY)
  ctx.stroke()
  ctx.restore()
}

/**
 * Scratched Paint Brush: etched jagged metal line
 */
export function drawScratchedSegment(
  ctx: CanvasRenderingContext2D,
  p1: StrokePoint,
  p2: StrokePoint,
  size: number,
  color: string,
  pressure = 0.8
) {
  const segLen = Math.hypot(p2.x - p1.x, p2.y - p1.y)
  const steps = Math.max(1, Math.ceil(segLen / Math.max(2, size * 0.15)))

  ctx.save()
  ctx.strokeStyle = normalizeColor(color)
  ctx.lineWidth = Math.max(1, size * 0.4)
  ctx.lineCap = 'butt'
  ctx.beginPath()
  ctx.moveTo(p1.x, p1.y)

  let prevX = p1.x
  let prevY = p1.y
  for (let i = 1; i <= steps; i++) {
    const t = i / steps
    const jitterX = (Math.random() - 0.5) * (size * 0.65)
    const jitterY = (Math.random() - 0.5) * (size * 0.65)
    const nx = p1.x + (p2.x - p1.x) * t + jitterX
    const ny = p1.y + (p2.y - p1.y) * t + jitterY
    ctx.lineTo(nx, ny)
    // Micro cross scratch
    if (Math.random() < 0.25) {
      const crossLen = 2 + Math.random() * size * 0.8
      ctx.moveTo(nx - crossLen, ny + crossLen)
      ctx.lineTo(nx + crossLen, ny - crossLen)
      ctx.moveTo(nx, ny)
    }
    prevX = nx
    prevY = ny
  }
  ctx.stroke()
  ctx.restore()
}

/**
 * Stipple Brush: dot matrix pointillism
 */
export function drawStippleSegment(
  ctx: CanvasRenderingContext2D,
  p1: StrokePoint,
  p2: StrokePoint,
  size: number,
  color: string,
  pressure = 0.8
) {
  const segLen = Math.hypot(p2.x - p1.x, p2.y - p1.y)
  const steps = Math.max(1, Math.ceil(segLen / Math.max(3, size * 0.2)))
  for (let i = 0; i <= steps; i++) {
    const t = i / steps
    const cx = p1.x + (p2.x - p1.x) * t
    const cy = p1.y + (p2.y - p1.y) * t
    drawScatter(ctx, cx, cy, size * 0.75, Math.max(4, Math.floor(10 * pressure)), color, pressure, 0.7, 1.8)
  }
}

/**
 * Rough Spray Brush: chunky, high-dispersion can
 */
export function drawRoughSpraySegment(
  ctx: CanvasRenderingContext2D,
  p1: StrokePoint,
  p2: StrokePoint,
  size: number,
  color: string,
  pressure = 0.8
) {
  drawLine(ctx, p1.x, p1.y, p2.x, p2.y, size * 0.7, color, pressure * 0.8)
  const segLen = Math.hypot(p2.x - p1.x, p2.y - p1.y)
  const steps = Math.max(1, Math.ceil(segLen / Math.max(4, size * 0.25)))
  for (let i = 0; i <= steps; i++) {
    const t = i / steps
    const cx = p1.x + (p2.x - p1.x) * t
    const cy = p1.y + (p2.y - p1.y) * t
    drawScatter(ctx, cx, cy, size * 1.35, 8, color, pressure * 0.85, 0.9, 3.2)
  }
}

// ─── Freehand Stroke Replay ────────────────────────────────────────────

export function renderFreehandStroke(ctx: CanvasRenderingContext2D, stroke: FreehandStroke) {
  if (!stroke.points || stroke.points.length === 0) return
  const pts = stroke.points
  const style = (stroke.style || 'spray') as BrushStyleId
  const size = Math.max(1, stroke.size || 10)
  const color = normalizeColor(stroke.color)
  const pressure = stroke.pressure || 0.8

  if (stroke.type === 'erase') {
    ctx.save()
    ctx.globalCompositeOperation = 'destination-out'
    for (let i = 1; i < pts.length; i++) {
      drawLine(ctx, pts[i - 1].x, pts[i - 1].y, pts[i].x, pts[i].y, size * 1.5, '#000000', 1.0)
    }
    ctx.restore()
    return
  }

  if (pts.length === 1) {
    drawDot(ctx, pts[0].x, pts[0].y, size, color, pressure)
    return
  }

  for (let i = 1; i < pts.length; i++) {
    const p1 = pts[i - 1]
    const p2 = pts[i]
    switch (style) {
      case 'chalk':
        drawChalkSegment(ctx, p1, p2, size, color, pressure)
        break
      case 'crayon':
        drawCrayonSegment(ctx, p1, p2, size, color, pressure)
        break
      case 'marker_bleed':
        drawMarkerBleedSegment(ctx, p1, p2, size, color, pressure)
        break
      case 'roller':
        drawRollerSegment(ctx, p1, p2, size, color, pressure)
        break
      case 'scratched':
        drawScratchedSegment(ctx, p1, p2, size, color, pressure)
        break
      case 'stipple':
        drawStippleSegment(ctx, p1, p2, size, color, pressure)
        break
      case 'rough_spray':
        drawRoughSpraySegment(ctx, p1, p2, size, color, pressure)
        break
      case 'airbrush':
        drawSoftDot(ctx, p2.x, p2.y, size * 2.2, color, pressure, 0.5)
        break
      case 'splatter':
        drawLine(ctx, p1.x, p1.y, p2.x, p2.y, size * 0.4, color, pressure)
        drawScatter(ctx, p2.x, p2.y, size * 1.4, 6, color, pressure, 0.8, 3.0)
        break
      case 'pen':
        drawLine(ctx, p1.x, p1.y, p2.x, p2.y, size * 0.3, color, pressure)
        break
      case 'calligraphy': {
        const a = Math.atan2(p2.y - p1.y, p2.x - p1.x)
        const w = Math.max(2, size * (0.4 + 0.6 * Math.abs(Math.sin(a + 0.8))))
        drawLine(ctx, p1.x, p1.y, p2.x, p2.y, w, color, pressure)
        break
      }
      case 'drip':
      case 'spray':
      default:
        drawLine(ctx, p1.x, p1.y, p2.x, p2.y, size, color, pressure)
        drawScatter(ctx, p2.x, p2.y, size * 0.8, 3, color, pressure * 0.6, 0.5, 1.8)
        break
    }
  }
}

// ─── Text Layer Rendering ──────────────────────────────────────────────

export function renderTextLayer(ctx: CanvasRenderingContext2D, layer: TextLayer) {
  if (!layer.text || layer.text.trim() === '') return

  ctx.save()
  ctx.translate(layer.x, layer.y)
  ctx.rotate((layer.rotation * Math.PI) / 180)
  ctx.scale(layer.scale, layer.scale)

  const fontStyle = layer.fontStyle === 'italic' ? 'italic ' : ''
  const fontWeight = layer.fontWeight === 'bold' ? 'bold ' : layer.fontWeight === '900' ? '900 ' : ''
  const fontFace = layer.font || 'Oswald'
  const fontSize = Math.max(12, layer.fontSize || 64)

  ctx.font = `${fontStyle}${fontWeight}${fontSize}px "${fontFace}", sans-serif`
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'

  // Letter spacing simulation
  const text = layer.text
  const metrics = ctx.measureText(text)
  const letterSpacing = layer.letterSpacing || 0

  // 1. Neon Glow pass
  if (layer.glow && layer.glow.enabled && layer.glow.blur > 0) {
    ctx.save()
    ctx.shadowColor = layer.glow.color || '#D6FF62'
    ctx.shadowBlur = layer.glow.blur * 1.5
    ctx.fillStyle = layer.glow.color || '#D6FF62'
    ctx.fillText(text, 0, 0)
    ctx.restore()
  }

  // 2. Drop Shadow pass
  if (layer.shadow && layer.shadow.enabled) {
    ctx.save()
    ctx.shadowColor = layer.shadow.color || '#000000'
    ctx.shadowBlur = layer.shadow.blur || 8
    ctx.shadowOffsetX = layer.shadow.offsetX || 4
    ctx.shadowOffsetY = layer.shadow.offsetY || 4
    ctx.fillStyle = layer.shadow.color || '#000000'
    ctx.fillText(text, 0, 0)
    ctx.restore()
  }

  // 3. Outline stroke pass
  if (layer.outline && layer.outline.enabled && layer.outline.width > 0) {
    ctx.save()
    ctx.strokeStyle = normalizeColor(layer.outline.color, '#000000')
    ctx.lineWidth = layer.outline.width * 2
    ctx.lineJoin = 'round'
    ctx.miterLimit = 2
    ctx.strokeText(text, 0, 0)
    ctx.restore()
  }

  // 4. Main Text fill
  ctx.fillStyle = normalizeColor(layer.color, '#FFFFFF')
  ctx.fillText(text, 0, 0)

  // 5. Splatter / Spray over letters
  if (layer.spray && layer.spray.enabled && layer.spray.count > 0) {
    const sprayColor = layer.color
    const halfW = metrics.width * 0.5
    const halfH = fontSize * 0.5
    for (let s = 0; s < layer.spray.count; s++) {
      const rx = (Math.random() - 0.5) * (halfW * 2 + layer.spray.spread)
      const ry = (Math.random() - 0.5) * (halfH * 2 + layer.spray.spread)
      drawScatter(ctx, rx, ry, 8, 3, sprayColor, 0.7, 0.6, 2.2)
    }
  }

  // 6. Drip effect running down from bottom edge
  if (layer.drip && layer.drip.enabled && layer.drip.count > 0) {
    const halfW = metrics.width * 0.45
    const bottomY = fontSize * 0.42
    const dripColor = layer.color
    const dripWidth = Math.max(2, layer.drip.width || 4)
    const dripLen = Math.max(10, layer.drip.length || 50)

    for (let d = 0; d < layer.drip.count; d++) {
      const dx = (d / Math.max(1, layer.drip.count - 1) - 0.5) * (halfW * 2) + (Math.random() - 0.5) * 12
      const curLen = dripLen * (0.6 + Math.random() * 0.8)
      ctx.save()
      ctx.strokeStyle = normalizeColor(dripColor)
      ctx.lineWidth = dripWidth
      ctx.lineCap = 'round'
      ctx.beginPath()
      ctx.moveTo(dx, bottomY)
      const endY = bottomY + curLen
      ctx.quadraticCurveTo(dx + (Math.random() - 0.5) * 8, bottomY + curLen * 0.5, dx, endY)
      ctx.stroke()
      // Drip bottom droplet
      drawDot(ctx, dx, endY, dripWidth * 1.5, dripColor, 1.0)
      ctx.restore()
    }
  }

  // 7. Distress weathering effect
  if (layer.distress && layer.distress.enabled && layer.distress.roughness > 0) {
    ctx.save()
    ctx.globalCompositeOperation = 'destination-out'
    const scratchCount = Math.floor(fontSize * layer.distress.roughness * 0.8)
    const halfW = metrics.width * 0.5
    for (let sc = 0; sc < scratchCount; sc++) {
      const sx = (Math.random() - 0.5) * halfW * 2
      const sy = (Math.random() - 0.5) * fontSize
      const slen = 4 + Math.random() * 16
      ctx.strokeStyle = 'rgba(0,0,0,0.85)'
      ctx.lineWidth = 0.8 + Math.random() * 1.5
      ctx.beginPath()
      ctx.moveTo(sx, sy)
      ctx.lineTo(sx + (Math.random() - 0.5) * slen, sy + (Math.random() - 0.5) * 4)
      ctx.stroke()
    }
    ctx.restore()
  }

  ctx.restore()
}

// ─── Image Layer Rendering with Filters & BG Removal ───────────────────

export async function renderImageLayer(ctx: CanvasRenderingContext2D, layer: ImageLayer) {
  const src = layer.dataUrl || layer.url
  if (!src) return

  let img: HTMLImageElement
  try {
    img = await loadCanvasImage(src)
  } catch (_) {
    return
  }

  // Create an offscreen canvas to apply filters and background keying
  const w = layer.width || img.width || 256
  const h = layer.height || img.height || 256
  const offscreen = document.createElement('canvas')
  offscreen.width = w
  offscreen.height = h
  const octx = offscreen.getContext('2d')
  if (!octx) return

  // Apply CSS filters on offscreen draw
  const filters = layer.filters || {
    brightness: 0,
    contrast: 0,
    monochrome: false,
    blur: 0,
    removeBg: false,
    removeBgThreshold: 25,
  }

  const filterStrings: string[] = []
  if (filters.brightness !== 0) filterStrings.push(`brightness(${100 + filters.brightness}%)`)
  if (filters.contrast !== 0) filterStrings.push(`contrast(${100 + filters.contrast}%)`)
  if (filters.monochrome) filterStrings.push('grayscale(100%)')
  if (filters.blur > 0) filterStrings.push(`blur(${filters.blur}px)`)

  if (filterStrings.length > 0) {
    octx.filter = filterStrings.join(' ')
  }

  octx.drawImage(img, 0, 0, w, h)
  octx.filter = 'none'

  // Background Removal (threshold keying)
  if (filters.removeBg) {
    try {
      const imgData = octx.getImageData(0, 0, w, h)
      const data = imgData.data
      // Sample top-left corner as key color
      const keyR = data[0]
      const keyG = data[1]
      const keyB = data[2]
      const threshold = (filters.removeBgThreshold || 25) * 2.55

      for (let i = 0; i < data.length; i += 4) {
        const dr = Math.abs(data[i] - keyR)
        const dg = Math.abs(data[i + 1] - keyG)
        const db = Math.abs(data[i + 2] - keyB)
        const dist = Math.sqrt(dr * dr + dg * dg + db * db)
        if (dist < threshold) {
          data[i + 3] = 0 // Transparent alpha
        }
      }
      octx.putImageData(imgData, 0, 0)
    } catch (_) {
      // Ignore CORS restrictions on external non-CORS images
    }
  }

  // Draw transformed offscreen canvas to main canvas
  ctx.save()
  ctx.translate(layer.x, layer.y)
  ctx.rotate((layer.rotation * Math.PI) / 180)
  ctx.scale(layer.flipX ? -1 : 1, layer.flipY ? -1 : 1)
  ctx.drawImage(offscreen, -w * 0.5, -h * 0.5, w, h)
  ctx.restore()
}

// ─── Stencil Layer Rendering ───────────────────────────────────────────

export function renderStencilLayer(ctx: CanvasRenderingContext2D, layer: StencilLayer) {
  const points = STENCILS[layer.stencilId] || STENCILS.Peak
  if (!points || points.length === 0) return

  ctx.save()
  ctx.translate(layer.x, layer.y)
  ctx.rotate((layer.rotation * Math.PI) / 180)

  const size = layer.size || 50
  const color = normalizeColor(layer.color, '#D6FF62')

  ctx.fillStyle = color
  ctx.beginPath()
  ctx.moveTo(points[0].x * (size / 10), points[0].y * (size / 10))
  for (let i = 1; i < points.length; i++) {
    ctx.lineTo(points[i].x * (size / 10), points[i].y * (size / 10))
  }
  ctx.closePath()
  ctx.fill()
  ctx.restore()
}

// ─── Unified Composition Renderer ──────────────────────────────────────

export async function renderComposition(
  ctx: CanvasRenderingContext2D,
  composition: GraffitiComposition,
  options?: { clear?: boolean }
) {
  if (options?.clear !== false) {
    ctx.clearRect(0, 0, composition.width || 1024, composition.height || 1024)
  }

  if (!composition.layers || composition.layers.length === 0) return

  for (const layer of composition.layers) {
    if (layer.visible === false) continue

    ctx.save()
    ctx.globalAlpha = clamp(layer.opacity !== undefined ? layer.opacity : 1.0, 0, 1)

    switch (layer.type) {
      case 'freehand': {
        const fh = layer as FreehandLayer
        if (fh.strokes) {
          for (const stroke of fh.strokes) {
            renderFreehandStroke(ctx, stroke)
          }
        }
        break
      }
      case 'text':
        renderTextLayer(ctx, layer as TextLayer)
        break
      case 'image':
        await renderImageLayer(ctx, layer as ImageLayer)
        break
      case 'stencil':
        renderStencilLayer(ctx, layer as StencilLayer)
        break
    }

    ctx.restore()
  }
}
