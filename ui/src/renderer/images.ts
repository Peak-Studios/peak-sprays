import type { ImageFilters } from '@/types/graffiti'

const imageCache = new Map<string, Promise<HTMLImageElement>>()
const processedCache = new Map<string, HTMLCanvasElement>()
const MAX_PROCESSED_ENTRIES = 64

export function clearImageCaches() {
  imageCache.clear()
  processedCache.clear()
}

export function loadImage(url: string): Promise<HTMLImageElement> {
  if (imageCache.has(url)) {
    return imageCache.get(url)!
  }

  const promise = new Promise<HTMLImageElement>((resolve, reject) => {
    const img = new Image()
    img.crossOrigin = 'anonymous'
    img.onload = () => resolve(img)
    img.onerror = () => {
      imageCache.delete(url)
      reject(new Error(`Failed to load image: ${url.substring(0, 64)}`))
    }
    img.src = url
  })

  imageCache.set(url, promise)
  return promise
}

function computeFilterKey(url: string, filters: ImageFilters, width: number, height: number): string {
  return `${url}_w${width}_h${height}_b${filters.brightness}_c${filters.contrast}_m${filters.monochrome ? 1 : 0}_bl${filters.blur}_rm${filters.removeBg ? 1 : 0}_th${filters.removeBgThreshold}`
}

export async function getProcessedImageCanvas(
  sourceUrl: string,
  filters: ImageFilters,
  targetWidth: number,
  targetHeight: number
): Promise<HTMLCanvasElement | null> {
  const cacheKey = computeFilterKey(sourceUrl, filters, targetWidth, targetHeight)
  if (processedCache.has(cacheKey)) {
    return processedCache.get(cacheKey)!
  }

  let img: HTMLImageElement
  try {
    img = await loadImage(sourceUrl)
  } catch {
    return null
  }

  const canvas = document.createElement('canvas')
  canvas.width = targetWidth
  canvas.height = targetHeight
  const ctx = canvas.getContext('2d')
  if (!ctx) return null

  // Draw scaled image
  ctx.drawImage(img, 0, 0, targetWidth, targetHeight)

  // Apply pixel filters if needed
  const hasPixelFilters =
    filters.brightness !== 0 ||
    filters.contrast !== 0 ||
    filters.monochrome ||
    filters.removeBg

  if (hasPixelFilters) {
    try {
      const imgData = ctx.getImageData(0, 0, targetWidth, targetHeight)
      const data = imgData.data

      const bMult = (filters.brightness || 0) * 1.5
      const contrast = filters.contrast || 0
      const cFactor = (259 * (contrast + 255)) / (255 * (259 - contrast))
      const removeBg = filters.removeBg === true
      const bgThreshold = (filters.removeBgThreshold || 25) * 2.55

      for (let i = 0; i < data.length; i += 4) {
        let r = data[i]
        let g = data[i + 1]
        let b = data[i + 2]
        let a = data[i + 3]

        if (a === 0) continue

        // Background removal (white/light luminance threshold)
        if (removeBg) {
          const lum = 0.299 * r + 0.587 * g + 0.114 * b
          if (lum >= 255 - bgThreshold) {
            data[i + 3] = 0
            continue
          }
        }

        // Brightness
        if (bMult !== 0) {
          r = Math.min(255, Math.max(0, r + bMult))
          g = Math.min(255, Math.max(0, g + bMult))
          b = Math.min(255, Math.max(0, b + bMult))
        }

        // Contrast
        if (contrast !== 0) {
          r = Math.min(255, Math.max(0, cFactor * (r - 128) + 128))
          g = Math.min(255, Math.max(0, cFactor * (g - 128) + 128))
          b = Math.min(255, Math.max(0, cFactor * (b - 128) + 128))
        }

        // Monochrome
        if (filters.monochrome) {
          const gray = 0.299 * r + 0.587 * g + 0.114 * b
          r = gray
          g = gray
          b = gray
        }

        data[i] = r
        data[i + 1] = g
        data[i + 2] = b
      }

      ctx.putImageData(imgData, 0, 0)
    } catch {
      // Ignore security / tainted canvas in edge cases
    }
  }

  // Apply blur filter if needed
  if (filters.blur && filters.blur > 0) {
    const blurCanvas = document.createElement('canvas')
    blurCanvas.width = targetWidth
    blurCanvas.height = targetHeight
    const bctx = blurCanvas.getContext('2d')
    if (bctx) {
      bctx.filter = `blur(${filters.blur}px)`
      bctx.drawImage(canvas, 0, 0)
      ctx.clearRect(0, 0, targetWidth, targetHeight)
      ctx.drawImage(blurCanvas, 0, 0)
    }
  }

  // Manage cache capacity
  if (processedCache.size >= MAX_PROCESSED_ENTRIES) {
    const oldestKey = processedCache.keys().next().value
    if (oldestKey) processedCache.delete(oldestKey)
  }
  processedCache.set(cacheKey, canvas)

  return canvas
}
