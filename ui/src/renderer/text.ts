import type { TextLayer } from '../types/graffiti.ts'
import { createSeededRandom } from './random.ts'
import { normalizeColor } from './brushes.ts'

/**
 * Ensures all custom fonts referenced in the document are loaded before drawing.
 */
export async function ensureFontsLoaded(fonts: string[]): Promise<void> {
  if (typeof document === 'undefined' || !document.fonts) return

  const fontPromises = fonts.map((font) => {
    return document.fonts.load(`bold 48px "${font}"`).catch(() => {
      // Graceful fallback to system font if custom font file is absent
    })
  })

  await Promise.all(fontPromises)
}

/**
 * Renders a styled text layer deterministically onto the canvas context.
 */
export function drawTextLayer(
  ctx: CanvasRenderingContext2D,
  layer: TextLayer,
  seedKey: string
): void {
  const text = layer.text
  if (!text || text.trim() === '') return

  const font = layer.font || 'Rock Salt'
  const fontSize = layer.fontSize || 72
  const fontWeight = layer.fontWeight || 'bold'
  const fontStyle = layer.fontStyle || 'normal'
  const color = normalizeColor(layer.color, '#FFFFFF')
  const scale = layer.scale || 1.0
  const letterSpacing = layer.letterSpacing || 0
  const lineHeight = layer.lineHeight || 1.1

  const rng = createSeededRandom(seedKey)

  ctx.save()

  // Translate to position and rotate
  ctx.translate(layer.x, layer.y)
  if (layer.rotation) {
    ctx.rotate((layer.rotation * Math.PI) / 180)
  }
  ctx.scale(scale, scale)

  ctx.font = `${fontStyle} ${fontWeight} ${fontSize}px "${font}", sans-serif`
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'

  const lines = text.split('\n')
  const totalLineHeight = fontSize * lineHeight
  const startY = -((lines.length - 1) * totalLineHeight) / 2

  // Function to render text line with letter spacing support
  const renderLine = (line: string, yOffset: number, mode: 'fill' | 'stroke') => {
    if (letterSpacing === 0) {
      if (mode === 'fill') ctx.fillText(line, 0, yOffset)
      else ctx.strokeText(line, 0, yOffset)
      return
    }

    // Manual letter spacing fallback for compatibility
    let totalWidth = 0
    const charWidths = []
    for (let c = 0; c < line.length; c++) {
      const w = ctx.measureText(line[c]).width + letterSpacing
      charWidths.push(w)
      totalWidth += w
    }

    let curX = -totalWidth / 2 + charWidths[0] / 2
    for (let c = 0; c < line.length; c++) {
      if (mode === 'fill') ctx.fillText(line[c], curX, yOffset)
      else ctx.strokeText(line[c], curX, yOffset)
      if (c < line.length - 1) {
        curX += (charWidths[c] + charWidths[c + 1]) / 2
      }
    }
  }

  // 1. Drop Shadow
  if (layer.shadow && layer.shadow.enabled) {
    ctx.save()
    ctx.shadowColor = normalizeColor(layer.shadow.color, '#000000')
    ctx.shadowBlur = layer.shadow.blur || 10
    ctx.shadowOffsetX = layer.shadow.offsetX || 4
    ctx.shadowOffsetY = layer.shadow.offsetY || 6
    ctx.fillStyle = normalizeColor(layer.shadow.color, '#000000')
    for (let l = 0; l < lines.length; l++) {
      renderLine(lines[l], startY + l * totalLineHeight, 'fill')
    }
    ctx.restore()
  }

  // 2. Neon Glow
  if (layer.glow && layer.glow.enabled) {
    ctx.save()
    ctx.shadowColor = normalizeColor(layer.glow.color, '#D6FF62')
    ctx.shadowBlur = layer.glow.blur || 20
    ctx.shadowOffsetX = 0
    ctx.shadowOffsetY = 0
    ctx.fillStyle = normalizeColor(layer.glow.color, '#D6FF62')
    for (let l = 0; l < lines.length; l++) {
      renderLine(lines[l], startY + l * totalLineHeight, 'fill')
    }
    ctx.restore()
  }

  // 3. Stroke Outline
  if (layer.outline && layer.outline.enabled) {
    ctx.save()
    ctx.strokeStyle = normalizeColor(layer.outline.color, '#000000')
    ctx.lineWidth = layer.outline.width || 6
    ctx.lineJoin = 'round'
    ctx.lineCap = 'round'
    for (let l = 0; l < lines.length; l++) {
      renderLine(lines[l], startY + l * totalLineHeight, 'stroke')
    }
    ctx.restore()
  }

  // 4. Main Lettering Fill
  ctx.fillStyle = color
  for (let l = 0; l < lines.length; l++) {
    renderLine(lines[l], startY + l * totalLineHeight, 'fill')
  }

  // 5. Glyph-Anchored Drips (runs dripping down from text)
  if (layer.drip && layer.drip.enabled) {
    const dripCount = Math.min(20, Math.max(1, layer.drip.count || 4))
    const maxLen = layer.drip.length || 60
    const dripColor = color

    ctx.fillStyle = dripColor
    ctx.strokeStyle = dripColor

    for (let d = 0; d < dripCount; d++) {
      const lineIdx = Math.floor(rng() * lines.length)
      const lineStr = lines[lineIdx]
      if (!lineStr) continue

      const charIdx = Math.floor(rng() * lineStr.length)
      const lineY = startY + lineIdx * totalLineHeight + fontSize * 0.4
      const fullWidth = ctx.measureText(lineStr).width
      const charOffset = (charIdx / Math.max(1, lineStr.length - 1) - 0.5) * fullWidth
      const dripLen = 15 + rng() * (maxLen - 15)
      const dripW = Math.max(2, (layer.drip.width || 4) * (0.8 + rng() * 0.4))

      // Line
      ctx.lineWidth = dripW * 0.6
      ctx.beginPath()
      ctx.moveTo(charOffset, lineY)
      ctx.lineTo(charOffset, lineY + dripLen)
      ctx.stroke()

      // Droplet teardrop at bottom
      ctx.beginPath()
      ctx.arc(charOffset, lineY + dripLen, dripW * 0.9, 0, Math.PI * 2)
      ctx.fill()
    }
  }

  // 6. Spray Aerosol Halo on Text
  if (layer.spray && layer.spray.enabled) {
    const count = Math.min(100, layer.spray.count || 20)
    const spread = layer.spray.spread || 25
    ctx.fillStyle = color

    for (let s = 0; s < count; s++) {
      const lineIdx = Math.floor(rng() * lines.length)
      const lineStr = lines[lineIdx]
      if (!lineStr) continue

      const fullWidth = ctx.measureText(lineStr).width
      const sx = (rng() - 0.5) * (fullWidth + spread)
      const sy = startY + lineIdx * totalLineHeight + (rng() - 0.5) * (fontSize + spread)

      ctx.beginPath()
      ctx.arc(sx, sy, 1 + rng() * 2, 0, Math.PI * 2)
      ctx.fill()
    }
  }

  // 7. Distress Weathering (cuts through text layer scratch surface)
  if (layer.distress && layer.distress.enabled) {
    ctx.globalCompositeOperation = 'destination-out'
    const roughness = Math.min(1, Math.max(0.05, layer.distress.roughness || 0.25))
    const cutCount = Math.floor(roughness * 120)

    for (let c = 0; c < cutCount; c++) {
      const lineIdx = Math.floor(rng() * lines.length)
      const lineStr = lines[lineIdx]
      if (!lineStr) continue

      const fullWidth = ctx.measureText(lineStr).width
      const cx = (rng() - 0.5) * fullWidth
      const cy = startY + lineIdx * totalLineHeight + (rng() - 0.5) * fontSize
      const cutW = 2 + rng() * 12
      const cutH = 1 + rng() * 3

      ctx.fillRect(cx, cy, cutW, cutH)
    }
    ctx.globalCompositeOperation = 'source-over'
  }

  ctx.restore()
}
