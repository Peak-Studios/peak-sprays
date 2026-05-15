/**
 * Peak Sprays - Canvas DUI Drawing Engine
 *
 * Receives messages via SendDuiMessage() from client Lua and renders
 * persistent spray strokes onto the projected DUI canvas.
 */
; (function () {
  const canvas = document.getElementById('sprayCanvas')
  const ctx = canvas.getContext('2d', { willReadFrequently: false })

  let canvasW = 1024
  let canvasH = 1024
  let strokes = []
  let redoStack = []
  let activeStroke = null
  let isDrawing = false
  let offscreen = null
  let snapshots = []
  let draftImage = null
  let redrawToken = 0
  const imageCache = new Map()

  function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value))
  }

  function hexToRgb(color) {
    const hex = typeof color === 'string' && color[0] === '#' ? color : '#000000'
    return {
      r: parseInt(hex.slice(1, 3), 16) || 0,
      g: parseInt(hex.slice(3, 5), 16) || 0,
      b: parseInt(hex.slice(5, 7), 16) || 0,
    }
  }

  function takeSnapshot() {
    try {
      const img = ctx.getImageData(0, 0, canvasW, canvasH)
      snapshots.push(img)
      if (snapshots.length > 100) snapshots.shift()
    } catch (_) {
      snapshots = []
    }
  }

  function nuiResourceName() {
    return window.GetParentResourceName ? window.GetParentResourceName() : 'peak-sprays'
  }

  function reportImageFailure(message) {
    fetch(`https://${nuiResourceName()}/imageLoadFailed`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message }),
    }).catch(() => { })
  }

  function loadImage(url) {
    if (imageCache.has(url)) return imageCache.get(url)

    const promise = new Promise((resolve, reject) => {
      const img = new Image()
      img.crossOrigin = 'anonymous'
      img.onload = () => resolve(img)
      img.onerror = () => reject(new Error('Image failed to load. The host may block CORS or the URL may be invalid.'))
      img.src = url
    })

    imageCache.set(url, promise)
    return promise
  }

  function normalizeImageOperation(image) {
    if (!image || image.type !== 'image') return null
    return {
      type: 'image',
      url: String(image.url || ''),
      x: Number(image.x) || canvasW * 0.5,
      y: Number(image.y) || canvasH * 0.5,
      width: Math.max(1, Number(image.width) || 256),
      height: Math.max(1, Number(image.height) || Number(image.width) || 256),
      rotation: Number(image.rotation) || 0,
      opacity: image.opacity !== undefined ? clamp(Number(image.opacity) || 1, 0.05, 1) : 1,
      flipX: image.flipX === true,
      flipY: image.flipY === true,
    }
  }

  function drawImageOperation(image, img) {
    const op = normalizeImageOperation(image)
    if (!op || !img) return

    ctx.save()
    ctx.globalAlpha = op.opacity
    ctx.translate(op.x, op.y)
    ctx.rotate(op.rotation * Math.PI / 180)
    ctx.scale(op.flipX ? -1 : 1, op.flipY ? -1 : 1)
    ctx.drawImage(img, -op.width * 0.5, -op.height * 0.5, op.width, op.height)
    ctx.restore()
  }

  function replayImageOperation(image, options = {}) {
    const op = normalizeImageOperation(image)
    if (!op || !op.url) return

    loadImage(op.url)
      .then((img) => {
        if (options.redrawWhenReady) {
          redrawCommitted()
        } else {
          drawImageOperation(op, img)
          if (options.snapshot) takeSnapshot()
        }
      })
      .catch((err) => {
        if (options.reportError) reportImageFailure(err.message)
      })
  }

  function replayPaintOperation(stroke) {
    if (!stroke || !stroke.points || stroke.points.length === 0) return
    const pts = stroke.points

    if (stroke.type === 'erase') {
      eraseCircle(pts[0].x, pts[0].y, stroke.size)
      for (let i = 1; i < pts.length; i++) {
        eraseSegment(pts[i - 1].x, pts[i - 1].y, pts[i].x, pts[i].y, stroke.size)
      }
    } else if (stroke.type === 'stencil') {
      ctx.save()
      ctx.fillStyle = stroke.color || '#000000'
      ctx.globalAlpha = stroke.pressure || 1.0
      ctx.beginPath()
      ctx.moveTo(pts[0].x, pts[0].y)
      for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y)
      ctx.closePath()
      ctx.fill()
      ctx.restore()
    } else {
      renderStyledDot(stroke, pts[0])
      for (let i = 1; i < pts.length; i++) {
        renderStyledSegment(stroke, pts[i - 1], pts[i], i, pts.length)
      }
    }
  }

  function redrawCommitted() {
    const token = ++redrawToken

    ;(async () => {
      ctx.clearRect(0, 0, canvasW, canvasH)
      snapshots = []
      takeSnapshot()

      for (let i = 0; i < strokes.length; i++) {
        if (token !== redrawToken) return
        if (strokes[i]?.type === 'image') {
          try {
            drawImageOperation(strokes[i], await loadImage(strokes[i].url))
          } catch (_) { /* ignore persisted image load failures */ }
        } else {
          replayPaintOperation(strokes[i])
        }
      }

      if (draftImage && token === redrawToken) {
        try {
          drawImageOperation(draftImage, await loadImage(draftImage.url))
        } catch (err) {
          reportImageFailure(err.message)
        }
      }

      if (token === redrawToken) takeSnapshot()
    })()
  }

  function drawDot(x, y, size, color, pressure) {
    ctx.save()
    ctx.globalAlpha = clamp(0.9 * (pressure || 1) + 0.1, 0, 1)
    ctx.fillStyle = color
    ctx.beginPath()
    ctx.arc(x, y, Math.max(0.5, 0.5 * size), 0, 2 * Math.PI)
    ctx.fill()
    ctx.restore()
  }

  function drawSoftDot(x, y, size, color, pressure, softness) {
    const radius = Math.max(1, size * 0.5)
    const rgb = hexToRgb(color)
    const alpha = clamp((pressure || 1) * 0.55, 0.04, 0.9)
    const gradient = ctx.createRadialGradient(x, y, 0, x, y, radius)
    gradient.addColorStop(0, `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${alpha})`)
    gradient.addColorStop(clamp(softness || 0.55, 0.15, 0.9), `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${alpha * 0.35})`)
    gradient.addColorStop(1, `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, 0)`)

    ctx.save()
    ctx.fillStyle = gradient
    ctx.beginPath()
    ctx.arc(x, y, radius, 0, 2 * Math.PI)
    ctx.fill()
    ctx.restore()
  }

  function drawLine(x1, y1, x2, y2, size, color, pressure) {
    ctx.save()
    ctx.globalAlpha = clamp(0.9 * (pressure || 1) + 0.1, 0, 1)
    ctx.strokeStyle = color
    ctx.lineWidth = Math.max(0.75, size)
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'
    ctx.beginPath()
    ctx.moveTo(x1, y1)
    ctx.lineTo(x2, y2)
    ctx.stroke()
    ctx.restore()
  }

  function drawVariableLine(x1, y1, x2, y2, size1, size2, color, pressure) {
    const segLen = Math.hypot(x2 - x1, y2 - y1)
    const steps = Math.max(1, Math.ceil(segLen / Math.max(1.5, Math.min(size1, size2))))
    for (let i = 1; i <= steps; i++) {
      const t0 = (i - 1) / steps
      const t1 = i / steps
      const w = size1 + (size2 - size1) * t1
      drawLine(
        x1 + (x2 - x1) * t0,
        y1 + (y2 - y1) * t0,
        x1 + (x2 - x1) * t1,
        y1 + (y2 - y1) * t1,
        w,
        color,
        pressure
      )
    }
  }

  function drawScatter(cx, cy, radius, count, color, pressure, minDot, maxDot) {
    if (count <= 0) return
    const rgb = hexToRgb(color)
    const spread = Math.max(0.5, radius)
    for (let i = 0; i < count; i++) {
      const u1 = Math.random()
      const u2 = Math.random()
      const mag = Math.sqrt(-2 * Math.log(u1 + 1e-4))
      const px = cx + mag * Math.cos(2 * Math.PI * u2) * spread * 0.45
      const py = cy + mag * Math.sin(2 * Math.PI * u2) * spread * 0.45
      const dotR = (minDot || 0.5) + ((maxDot || 2.0) - (minDot || 0.5)) * Math.random()
      const alpha = clamp((pressure || 1) * (0.25 + 0.65 * Math.random()), 0, 1)
      ctx.beginPath()
      ctx.arc(px, py, dotR, 0, 2 * Math.PI)
      ctx.fillStyle = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${alpha})`
      ctx.fill()
    }
  }

  function renderLegacySprayDot(x, y, size, density, color, pressure, scatter) {
    if (scatter <= 0.05) {
      drawDot(x, y, size, color, pressure)
    } else if (scatter < 0.3) {
      drawDot(x, y, size, color, 0.8 * pressure)
      drawScatter(x, y, 0.5 * size, Math.floor(density * scatter * 0.5), color, 0.3 * pressure)
    } else {
      drawScatter(x, y, size, Math.floor(density * scatter * 1.5), color, 0.8 * pressure)
    }
  }

  function renderLegacySpraySegment(x1, y1, x2, y2, size, density, color, pressure, scatter) {
    if (scatter <= 0.05) {
      drawLine(x1, y1, x2, y2, size, color, pressure)
      return
    }

    const segLen = Math.hypot(x2 - x1, y2 - y1)
    if (scatter < 0.3) {
      drawLine(x1, y1, x2, y2, size, color, pressure * (1 - scatter))
      const steps = Math.max(1, Math.floor(segLen / (0.5 * size)))
      for (let i = 0; i <= steps; i++) {
        const t = steps === 0 ? 0 : i / steps
        drawScatter(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, size * scatter, Math.floor(density * scatter * 0.3), color, pressure * scatter)
      }
      return
    }

    const steps = Math.max(1, Math.floor(segLen / (0.3 * size)))
    for (let i = 0; i <= steps; i++) {
      const t = steps === 0 ? 0 : i / steps
      drawScatter(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, size, Math.floor(density * pressure), color, 0.7 * pressure)
    }
  }

  function renderStyledDot(stroke, point) {
    const style = stroke.style || 'spray'
    const size = Math.max(1, stroke.size || 10)
    const density = Math.max(1, stroke.density || 25)
    const pressure = stroke.pressure || 0.8
    const color = stroke.color || '#000000'
    const scatter = stroke.scatter !== undefined ? stroke.scatter : 1

    if (style === 'pen') {
      drawDot(point.x, point.y, size, color, pressure)
    } else if (style === 'calligraphy') {
      drawDot(point.x, point.y, size * 0.9, color, pressure)
    } else if (style === 'splatter') {
      drawScatter(point.x, point.y, size * 1.25, Math.ceil(density * 1.25), color, pressure, size * 0.08, size * 0.32)
      drawDot(point.x, point.y, size * 0.35, color, pressure * 0.65)
    } else if (style === 'airbrush') {
      drawSoftDot(point.x, point.y, size * 2.2, color, pressure, 0.45)
      drawScatter(point.x, point.y, size * 0.9, Math.ceil(density * 0.25), color, pressure * 0.25, 0.4, 1.2)
    } else if (style === 'drip') {
      drawDot(point.x, point.y, size * 0.75, color, pressure)
      drawScatter(point.x, point.y, size * 0.35, Math.ceil(density * 0.18), color, pressure * 0.25, 0.35, 1.0)
    } else if (style === 'drip-run') {
      drawDot(point.x, point.y, size * 0.75, color, pressure)
    } else {
      renderLegacySprayDot(point.x, point.y, size, density, color, pressure, scatter)
    }
  }

  function renderStyledSegment(stroke, prev, point, index, total) {
    const style = stroke.style || 'spray'
    const size = Math.max(1, stroke.size || 10)
    const density = Math.max(1, stroke.density || 25)
    const pressure = stroke.pressure || 0.8
    const color = stroke.color || '#000000'
    const scatter = stroke.scatter !== undefined ? stroke.scatter : 1
    const segLen = Math.hypot(point.x - prev.x, point.y - prev.y)

    if (style === 'pen') {
      drawLine(prev.x, prev.y, point.x, point.y, size, color, pressure)
    } else if (style === 'calligraphy') {
      const a = Math.atan2(point.y - prev.y, point.x - prev.x)
      const w1 = Math.max(2, size * (0.55 + 0.45 * Math.abs(Math.sin(a + 0.8))))
      const w2 = Math.max(2, size * (0.5 + 0.5 * Math.abs(Math.sin(a + 1.05))))
      drawVariableLine(prev.x, prev.y, point.x, point.y, w1, w2, color, pressure)
    } else if (style === 'splatter') {
      const steps = Math.max(1, Math.ceil(segLen / Math.max(4, size * 0.55)))
      for (let i = 0; i <= steps; i++) {
        const t = steps === 0 ? 0 : i / steps
        drawScatter(prev.x + (point.x - prev.x) * t, prev.y + (point.y - prev.y) * t, size * 1.15, Math.ceil(density * 0.55), color, pressure, size * 0.06, size * 0.28)
      }
    } else if (style === 'airbrush') {
      const steps = Math.max(1, Math.ceil(segLen / Math.max(3, size * 0.35)))
      for (let i = 0; i <= steps; i++) {
        const t = steps === 0 ? 0 : i / steps
        drawSoftDot(prev.x + (point.x - prev.x) * t, prev.y + (point.y - prev.y) * t, size * 2.0, color, pressure, 0.5)
      }
    } else if (style === 'drip') {
      drawLine(prev.x, prev.y, point.x, point.y, size * 0.58, color, pressure * 0.9)
      if (density > 1) {
        const steps = Math.max(1, Math.ceil(segLen / Math.max(6, size * 1.3)))
        for (let i = 0; i <= steps; i++) {
          const t = steps === 0 ? 0 : i / steps
          drawScatter(
            prev.x + (point.x - prev.x) * t,
            prev.y + (point.y - prev.y) * t,
            size * 0.42,
            Math.ceil(density * scatter * 0.18),
            color,
            pressure * 0.24,
            0.35,
            1.0
          )
        }
      }
    } else if (style === 'drip-run') {
      const t = point.t !== undefined ? point.t : index / Math.max(1, total - 1)
      const baseWidth = Math.min(size, 7)
      const w1 = Math.max(0.85, baseWidth * (0.82 - clamp(t, 0, 1) * 0.42))
      const w2 = Math.max(0.65, baseWidth * (0.76 - clamp(t + 0.08, 0, 1) * 0.48))
      drawVariableLine(prev.x, prev.y, point.x, point.y, w1, w2, color, pressure)
      if (t >= 0.98 || (index === total - 1 && total > 2 && point.t === undefined)) {
        drawDot(point.x, point.y, baseWidth * 0.95, color, pressure * 0.9)
        drawSoftDot(point.x, point.y, baseWidth * 1.45, color, pressure * 0.28, 0.35)
      }
    } else {
      renderLegacySpraySegment(prev.x, prev.y, point.x, point.y, size, density, color, pressure, scatter)
    }
  }

  function eraseCircle(x, y, radius) {
    ctx.save()
    ctx.beginPath()
    ctx.arc(x, y, radius, 0, 2 * Math.PI)
    ctx.clip()
    ctx.clearRect(x - radius, y - radius, 2 * radius, 2 * radius)
    ctx.restore()
  }

  function eraseSegment(x1, y1, x2, y2, radius) {
    const segLen = Math.hypot(x2 - x1, y2 - y1)
    const steps = Math.max(1, Math.floor(segLen / (0.3 * radius)))
    for (let i = 0; i <= steps; i++) {
      const t = steps === 0 ? 0 : i / steps
      eraseCircle(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, radius)
    }
  }

  function replayStroke(stroke) {
    if (!stroke) return
    if (stroke.type === 'image') {
      replayImageOperation(stroke, { redrawWhenReady: true, reportError: false })
    } else {
      replayPaintOperation(stroke)
    }
  }

  window.addEventListener('message', function (event) {
    let data = event.data
    if (typeof data === 'string') {
      try { data = JSON.parse(data) } catch (_) { return }
    }
    if (!data || !data.action) return

    switch (data.action) {
      case 'init': {
        canvasW = data.width || 1024
        canvasH = data.height || 1024
        canvas.width = canvasW
        canvas.height = canvasH
        ctx.clearRect(0, 0, canvasW, canvasH)
        offscreen = document.createElement('canvas')
        offscreen.width = canvasW
        offscreen.height = canvasH
        offscreen.getContext('2d')
        strokes = []
        redoStack = []
        snapshots = []
        activeStroke = null
        isDrawing = false
        draftImage = null
        takeSnapshot()
        break
      }

      case 'startStroke': {
        isDrawing = true
        redoStack = []
        activeStroke = {
          type: data.type || 'paint',
          style: data.style || undefined,
          color: data.color || '#000000',
          size: data.size || 10,
          density: data.density || 25,
          pressure: data.pressure || 0.8,
          scatter: data.scatter !== undefined ? data.scatter : 1,
          points: [{ x: data.x, y: data.y, t: data.t }],
        }
        if (activeStroke.type === 'erase') {
          eraseCircle(data.x, data.y, activeStroke.size)
        } else {
          renderStyledDot(activeStroke, activeStroke.points[0])
        }
        break
      }

      case 'addPoint': {
        if (!isDrawing || !activeStroke) break
        const prev = activeStroke.points[activeStroke.points.length - 1]
        const point = { x: data.x, y: data.y, t: data.t }
        if (data.pressure !== undefined) activeStroke.pressure = data.pressure
        if (data.size !== undefined) activeStroke.size = data.size
        if (data.density !== undefined) activeStroke.density = data.density
        if (data.scatter !== undefined) activeStroke.scatter = data.scatter
        if (data.style !== undefined) activeStroke.style = data.style
        activeStroke.points.push(point)
        if (activeStroke.type === 'erase') {
          eraseSegment(prev.x, prev.y, point.x, point.y, activeStroke.size)
        } else {
          renderStyledSegment(activeStroke, prev, point, activeStroke.points.length - 1, activeStroke.points.length)
        }
        break
      }

      case 'endStroke': {
        if (isDrawing && activeStroke) {
          isDrawing = false
          strokes.push(activeStroke)
          activeStroke = null
          takeSnapshot()
        }
        break
      }

      case 'undo': {
        if (strokes.length === 0) break
        const undone = strokes.pop()
        redoStack.push(undone)
        if (undone?.type === 'image') {
          redrawCommitted()
        } else if (snapshots.length > 1) {
          snapshots.pop()
          const idx = snapshots.length - 1
          if (idx >= 0) ctx.putImageData(snapshots[idx], 0, 0)
        } else {
          ctx.clearRect(0, 0, canvasW, canvasH)
        }
        break
      }

      case 'redo': {
        if (redoStack.length === 0) break
        const redone = redoStack.pop()
        strokes.push(redone)
        replayStroke(redone)
        if (redone?.type !== 'image') takeSnapshot()
        break
      }

      case 'loadStrokes': {
        const append = data.append || false
        if (!append) {
          ctx.clearRect(0, 0, canvasW, canvasH)
          snapshots = []
          strokes = []
          redoStack = []
          takeSnapshot()
        }
        const incoming = data.strokes || []
        for (let i = 0; i < incoming.length; i++) {
          strokes.push(incoming[i])
        }
        redrawCommitted()
        break
      }

      case 'updateActivePreview': {
        if (!data.stroke || !data.stroke.points || data.stroke.points.length === 0) break
        // To avoid ghosting/doubling, we only render the latest segment
        const pts = data.stroke.points
        if (pts.length === 1) {
          renderStyledDot(data.stroke, pts[0])
        } else {
          const prev = pts[pts.length - 2]
          const curr = pts[pts.length - 1]
          renderStyledSegment(data.stroke, prev, curr, pts.length - 1, pts.length)
        }
        break
      }

      case 'drawStroke': {
        if (!data.stroke) break
        if (data.stroke.type !== 'image' && (!data.stroke.points || data.stroke.points.length === 0)) break
        strokes.push(data.stroke)
        replayStroke(data.stroke)
        if (data.stroke.type !== 'image') takeSnapshot()
        break
      }

      case 'clear': {
        ctx.clearRect(0, 0, canvasW, canvasH)
        strokes = []
        redoStack = []
        snapshots = []
        activeStroke = null
        isDrawing = false
        draftImage = null
        takeSnapshot()
        break
      }

      case 'fullRedraw': {
        redrawCommitted()
        break
      }

      case 'getScreenshot': {
        try {
          const thumb = document.createElement('canvas')
          thumb.width = 256
          thumb.height = 256
          const tctx = thumb.getContext('2d')
          tctx.fillStyle = '#1a1a1a'
          tctx.fillRect(0, 0, 256, 256)
          tctx.drawImage(canvas, 0, 0, 256, 256)
          const base64 = thumb.toDataURL('image/jpeg', 0.7).split(',')[1]
          const urls = ['https://peak-sprays/screenshotReady', '/screenshotReady']
          for (const url of urls) {
            fetch(url, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ base64 }),
            }).catch(() => { })
          }
        } catch (_) { /* ignore */ }
        break
      }

      case 'updateBrush': {
        if (activeStroke) {
          if (data.size !== undefined) activeStroke.size = data.size
          if (data.density !== undefined) activeStroke.density = data.density
          if (data.color !== undefined) activeStroke.color = data.color
          if (data.pressure !== undefined) activeStroke.pressure = data.pressure
          if (data.scatter !== undefined) activeStroke.scatter = data.scatter
          if (data.style !== undefined) activeStroke.style = data.style
        }
        break
      }

      case 'stampStencil': {
        const points = data.points || []
        const color = data.color || '#000000'
        const size = data.size || 10
        const x = data.x
        const y = data.y
        const stencilStroke = {
          type: 'stencil',
          style: 'stencil',
          color,
          size,
          points: points.map(p => ({ x: x + p.x * (size / 10), y: y + p.y * (size / 10) })),
          pressure: 1.0,
        }

        strokes.push(stencilStroke)
        replayStroke(stencilStroke)
        takeSnapshot()
        break
      }

      case 'addImage': {
        draftImage = normalizeImageOperation(data.image)
        replayImageOperation(draftImage, { redrawWhenReady: true, reportError: true })
        break
      }

      case 'updateImage': {
        draftImage = normalizeImageOperation(data.image)
        redrawCommitted()
        break
      }

      case 'commitImage': {
        const image = normalizeImageOperation(data.image || draftImage)
        if (!image) break
        strokes.push(image)
        draftImage = null
        redoStack = []
        redrawCommitted()
        break
      }

      case 'cancelImage': {
        draftImage = null
        redrawCommitted()
        break
      }
    }
  })

  canvas.width = canvasW
  canvas.height = canvasH
  ctx.clearRect(0, 0, canvasW, canvasH)
})()
