import type { FreehandStroke, StrokePoint } from '../types/graffiti.ts'
import { createSeededRandom } from './random.ts'

export function normalizeColor(color?: string, fallback = '#000000'): string {
  if (!color || typeof color !== 'string') return fallback
  const hex = color.trim().replace(/[^a-fA-F0-9]/g, '')
  if (hex.length === 3) {
    return '#' + hex.split('').map((c) => c + c).join('').toUpperCase()
  } else if (hex.length >= 6) {
    return '#' + hex.slice(0, 6).toUpperCase()
  }
  return fallback
}

export function hexToRgb(color: string): { r: number; g: number; b: number } {
  const hex = normalizeColor(color)
  return {
    r: parseInt(hex.slice(1, 3), 16) || 0,
    g: parseInt(hex.slice(3, 5), 16) || 0,
    b: parseInt(hex.slice(5, 7), 16) || 0,
  }
}

/**
 * Draws a textured freehand stroke on the given 2D context deterministically.
 */
export function drawTexturedStroke(
  ctx: CanvasRenderingContext2D,
  stroke: FreehandStroke,
  seedKey: string
): void {
  const points = stroke.points
  if (!points || points.length === 0) return

  if (stroke.type === 'erase') {
    ctx.save()
    ctx.globalCompositeOperation = 'destination-out'
    ctx.lineWidth = Math.max(1, stroke.size || 14)
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'
    ctx.beginPath()
    ctx.moveTo(points[0].x, points[0].y)
    for (let i = 1; i < points.length; i++) {
      ctx.lineTo(points[i].x, points[i].y)
    }
    ctx.stroke()
    ctx.restore()
    return
  }

  const style = stroke.style || 'spray'
  const size = Math.max(1, stroke.size || 14)
  const color = normalizeColor(stroke.color, '#D6FF62')
  const rgb = hexToRgb(color)
  const rng = createSeededRandom(seedKey)

  ctx.save()

  switch (style) {
    case 'spray': {
      // Standard aerosol spray with soft falloff
      for (let i = 0; i < points.length; i++) {
        const pt = points[i]
        const pressure = pt.pressure !== undefined ? pt.pressure : (stroke.pressure || 0.85)
        const density = Math.floor((stroke.density || 25) * pressure)
        const radius = size * pressure

        for (let d = 0; d < density; d++) {
          const angle = rng() * Math.PI * 2
          const dist = rng() * radius
          const px = pt.x + Math.cos(angle) * dist
          const py = pt.y + Math.sin(angle) * dist
          const alpha = (1 - dist / radius) * 0.45 * pressure

          ctx.fillStyle = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${alpha.toFixed(3)})`
          ctx.beginPath()
          ctx.arc(px, py, 1.2, 0, Math.PI * 2)
          ctx.fill()
        }
      }
      break
    }

    case 'rough_spray': {
      // High pressure bursts with aggressive droplets
      for (let i = 0; i < points.length; i++) {
        const pt = points[i]
        const pressure = pt.pressure !== undefined ? pt.pressure : 0.9
        const density = Math.floor(35 * pressure)
        const radius = size * 1.3

        for (let d = 0; d < density; d++) {
          const angle = rng() * Math.PI * 2
          const dist = Math.pow(rng(), 1.5) * radius
          const px = pt.x + Math.cos(angle) * dist
          const py = pt.y + Math.sin(angle) * dist
          const dotSize = 0.8 + rng() * 2.8

          ctx.fillStyle = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${(0.35 + rng() * 0.5).toFixed(3)})`
          ctx.beginPath()
          ctx.arc(px, py, dotSize, 0, Math.PI * 2)
          ctx.fill()
        }
      }
      break
    }

    case 'chalk': {
      // Gritty, porous powder grain with toothy edges
      for (let i = 0; i < points.length; i++) {
        const pt = points[i]
        const radius = size * 0.9
        const count = 30

        for (let c = 0; c < count; c++) {
          const ox = (rng() - 0.5) * radius * 2
          const oy = (rng() - 0.5) * radius * 2
          if (ox * ox + oy * oy > radius * radius) continue

          ctx.fillStyle = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${(0.15 + rng() * 0.4).toFixed(3)})`
          ctx.fillRect(pt.x + ox, pt.y + oy, 2, 2)
        }
      }
      break
    }

    case 'crayon': {
      // Waxy core with texture voids
      ctx.strokeStyle = color
      ctx.lineWidth = size
      ctx.lineCap = 'round'
      ctx.lineJoin = 'round'
      ctx.beginPath()
      ctx.moveTo(points[0].x, points[0].y)
      for (let i = 1; i < points.length; i++) {
        ctx.lineTo(points[i].x, points[i].y)
      }
      ctx.stroke()

      // Add toothy wax voids
      ctx.globalCompositeOperation = 'destination-out'
      for (let i = 0; i < points.length; i++) {
        const pt = points[i]
        for (let v = 0; v < 8; v++) {
          const vx = pt.x + (rng() - 0.5) * size * 0.8
          const vy = pt.y + (rng() - 0.5) * size * 0.8
          ctx.fillRect(vx, vy, 1.5, 1.5)
        }
      }
      ctx.globalCompositeOperation = 'source-over'
      break
    }

    case 'marker_bleed': {
      // Fat wet chisel ink with edge feathering
      ctx.strokeStyle = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, 0.9)`
      ctx.lineWidth = size * 1.1
      ctx.lineCap = 'square'
      ctx.lineJoin = 'miter'
      ctx.beginPath()
      ctx.moveTo(points[0].x, points[0].y)
      for (let i = 1; i < points.length; i++) {
        ctx.lineTo(points[i].x, points[i].y)
      }
      ctx.stroke()

      // Feathers
      for (let i = 0; i < points.length; i += 2) {
        const pt = points[i]
        for (let b = 0; b < 6; b++) {
          const angle = rng() * Math.PI * 2
          const dist = (size * 0.5) + rng() * 6
          ctx.fillStyle = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, 0.2)`
          ctx.beginPath()
          ctx.arc(pt.x + Math.cos(angle) * dist, pt.y + Math.sin(angle) * dist, 1.5, 0, Math.PI * 2)
          ctx.fill()
        }
      }
      break
    }

    case 'roller': {
      // Wide flat track with defined edge tracks
      ctx.strokeStyle = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, 0.85)`
      ctx.lineWidth = size * 2.2
      ctx.lineCap = 'butt'
      ctx.lineJoin = 'round'
      ctx.beginPath()
      ctx.moveTo(points[0].x, points[0].y)
      for (let i = 1; i < points.length; i++) {
        ctx.lineTo(points[i].x, points[i].y)
      }
      ctx.stroke()
      break
    }

    case 'calligraphy':
    case 'pen': {
      // Angle-dynamic chisel nib
      ctx.fillStyle = color
      const half = size * 0.6
      const angleRad = Math.PI / 4 // 45 deg nib
      const cosA = Math.cos(angleRad) * half
      const sinA = Math.sin(angleRad) * half

      for (let i = 0; i < points.length; i++) {
        const pt = points[i]
        ctx.beginPath()
        ctx.moveTo(pt.x - cosA, pt.y - sinA)
        ctx.lineTo(pt.x + cosA, pt.y + sinA)
        if (i < points.length - 1) {
          const next = points[i + 1]
          ctx.lineTo(next.x + cosA, next.y + sinA)
          ctx.lineTo(next.x - cosA, next.y - sinA)
        }
        ctx.closePath()
        ctx.fill()
      }
      break
    }

    case 'splatter': {
      // Impact paint bombs with long directional drips
      for (let i = 0; i < points.length; i++) {
        const pt = points[i]
        // Main impact circle
        ctx.fillStyle = color
        ctx.beginPath()
        ctx.arc(pt.x, pt.y, size * 0.5, 0, Math.PI * 2)
        ctx.fill()

        // Splatter droplets
        const numDrops = 10 + Math.floor(rng() * 15)
        for (let d = 0; d < numDrops; d++) {
          const angle = rng() * Math.PI * 2
          const dist = (size * 0.6) + rng() * size * 2.0
          const dropSize = 0.5 + rng() * 2.5
          ctx.beginPath()
          ctx.arc(pt.x + Math.cos(angle) * dist, pt.y + Math.sin(angle) * dist, dropSize, 0, Math.PI * 2)
          ctx.fill()
        }
      }
      break
    }

    case 'airbrush': {
      // Ultra-soft gradient fade
      for (let i = 0; i < points.length; i++) {
        const pt = points[i]
        const grad = ctx.createRadialGradient(pt.x, pt.y, 0, pt.x, pt.y, size * 1.5)
        grad.addColorStop(0, `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, 0.25)`)
        grad.addColorStop(1, `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, 0)`)
        ctx.fillStyle = grad
        ctx.beginPath()
        ctx.arc(pt.x, pt.y, size * 1.5, 0, Math.PI * 2)
        ctx.fill()
      }
      break
    }

    case 'drip': {
      // Running drips downwards from stroke points
      ctx.strokeStyle = color
      ctx.lineWidth = size
      ctx.lineCap = 'round'
      ctx.lineJoin = 'round'
      ctx.beginPath()
      ctx.moveTo(points[0].x, points[0].y)
      for (let i = 1; i < points.length; i++) {
        ctx.lineTo(points[i].x, points[i].y)
      }
      ctx.stroke()

      // Downward paint runs
      for (let i = 0; i < points.length; i += 3) {
        if (rng() > 0.4) {
          const pt = points[i]
          const dripLen = 20 + rng() * 80
          const dripWidth = Math.max(2, size * 0.35)

          ctx.fillStyle = color
          ctx.beginPath()
          ctx.arc(pt.x, pt.y + dripLen, dripWidth * 0.9, 0, Math.PI * 2)
          ctx.fill()

          ctx.strokeStyle = color
          ctx.lineWidth = dripWidth * 0.7
          ctx.beginPath()
          ctx.moveTo(pt.x, pt.y)
          ctx.lineTo(pt.x, pt.y + dripLen)
          ctx.stroke()
        }
      }
      break
    }

    case 'stipple': {
      // Fine dot matrix scatter
      for (let i = 0; i < points.length; i++) {
        const pt = points[i]
        const radius = size * 1.2
        const dots = Math.floor(15 + rng() * 20)
        for (let d = 0; d < dots; d++) {
          const angle = rng() * Math.PI * 2
          const dist = Math.sqrt(rng()) * radius
          const px = pt.x + Math.cos(angle) * dist
          const py = pt.y + Math.sin(angle) * dist
          const dotRadius = 0.6 + rng() * 1.0
          ctx.fillStyle = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${(0.4 + rng() * 0.5).toFixed(3)})`
          ctx.beginPath()
          ctx.arc(px, py, dotRadius, 0, Math.PI * 2)
          ctx.fill()
        }
      }
      break
    }

    case 'scratched': {
      // Multiple parallel jittery groove lines with gaps
      const scratchLines = 4
      for (let s = 0; s < scratchLines; s++) {
        const offset = (s - (scratchLines - 1) / 2) * (size / scratchLines) * 1.2
        ctx.strokeStyle = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, 0.85)`
        ctx.lineWidth = Math.max(1, size * 0.15)
        ctx.lineCap = 'butt'
        ctx.beginPath()
        let drawing = false
        for (let i = 0; i < points.length; i++) {
          if (rng() > 0.15) {
            const jx = (rng() - 0.5) * 2
            const jy = (rng() - 0.5) * 2
            const px = points[i].x + offset + jx
            const py = points[i].y + jy
            if (!drawing) {
              ctx.moveTo(px, py)
              drawing = true
            } else {
              ctx.lineTo(px, py)
            }
          } else {
            drawing = false
          }
        }
        ctx.stroke()
      }
      break
    }

    default: {
      // Fallback clean path
      ctx.strokeStyle = color
      ctx.lineWidth = size
      ctx.lineCap = 'round'
      ctx.lineJoin = 'round'
      ctx.beginPath()
      ctx.moveTo(points[0].x, points[0].y)
      for (let i = 1; i < points.length; i++) {
        ctx.lineTo(points[i].x, points[i].y)
      }
      ctx.stroke()
      break
    }
  }

  ctx.restore()
}
