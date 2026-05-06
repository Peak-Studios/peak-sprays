/**
 * Peak Sprays - Canvas DUI Drawing Engine
 * Faithfully reconstructed from the original canvas-BSy6Z3YE.js
 *
 * Receives messages via SendDuiMessage() from painting.lua (client/painting.lua).
 * The canvas is projected onto the game world via CreateDui + DrawSpritePoly.
 */
; (function () {
  const canvas = document.getElementById('sprayCanvas')
  const ctx = canvas.getContext('2d', { willReadFrequently: false })

  // ─── State ────────────────────────────────────────────────────────────
  let canvasW = 1024   // set by 'init'
  let canvasH = 1024
  let strokes = []     // committed stroke history (undo stack)
  let redoStack = []     // redo buffer
  let activeStroke = null // the stroke currently being drawn
  let isDrawing = false

  // offscreen scratch canvas (created on init, unused after – original creates it but never draws on it)
  let offscreen = null

  // Snapshot stack for pixel-exact undo
  let snapshots = []

  // ─── Snapshot ─────────────────────────────────────────────────────────
  function takeSnapshot() {
    const img = ctx.getImageData(0, 0, canvasW, canvasH)
    snapshots.push(img)
    if (snapshots.length > 100) snapshots.shift()
  }

  // ─── Drawing primitives ───────────────────────────────────────────────

  /** Hard filled circle */
  function drawDot(x, y, size, color, pressure) {
    ctx.save()
    ctx.globalAlpha = Math.min(1, 0.9 * pressure + 0.1)
    ctx.fillStyle = color
    ctx.beginPath()
    ctx.arc(x, y, 0.5 * size, 0, 2 * Math.PI)
    ctx.fill()
    ctx.restore()
  }

  /** Hard line segment */
  function drawLine(x1, y1, x2, y2, size, color, pressure) {
    ctx.save()
    ctx.globalAlpha = Math.min(1, 0.9 * pressure + 0.1)
    ctx.strokeStyle = color
    ctx.lineWidth = size
    ctx.lineCap = 'round'
    ctx.lineJoin = 'round'
    ctx.beginPath()
    ctx.moveTo(x1, y1)
    ctx.lineTo(x2, y2)
    ctx.stroke()
    ctx.restore()
  }

  /**
   * Gaussian scatter cloud (Box-Muller transform).
   * Matches the original 'f' function exactly.
   */
  function drawScatter(cx, cy, radius, count, color, pressure) {
    if (count <= 0) return
    const r = parseInt(color.slice(1, 3), 16)
    const g = parseInt(color.slice(3, 5), 16)
    const b = parseInt(color.slice(5, 7), 16)
    for (let i = 0; i < count; i++) {
      const u1 = Math.random()
      const u2 = Math.random()
      const mag = Math.sqrt(-2 * Math.log(u1 + 1e-4))
      const px = cx + mag * Math.cos(2 * Math.PI * u2) * radius * 0.45
      const py = cy + mag * Math.sin(2 * Math.PI * u2) * radius * 0.45
      const dotR = 0.5 + 1.5 * Math.random()
      const alpha = pressure * (0.3 + 0.7 * Math.random())
      ctx.beginPath()
      ctx.arc(px, py, dotR, 0, 2 * Math.PI)
      ctx.fillStyle = `rgba(${r}, ${g}, ${b}, ${alpha})`
      ctx.fill()
    }
  }

  /** Render a spray dot at a single point (start of stroke) — 'p' function */
  function renderSprayDot(x, y, size, density, color, pressure, scatter) {
    if (scatter <= 0.05) {
      drawDot(x, y, size, color, pressure)
    } else if (scatter < 0.3) {
      drawDot(x, y, size, color, 0.8 * pressure)
      drawScatter(x, y, 0.5 * size, Math.floor(density * scatter * 0.5), color, 0.3 * pressure)
    } else {
      // full scatter
      drawScatter(x, y, size, Math.floor(density * scatter * 1.5), color, 0.8 * pressure)
    }
  }

  /** Render a spray segment between two points — 'y' function */
  function renderSpraySegment(x1, y1, x2, y2, size, density, color, pressure, scatter) {
    if (scatter <= 0.05) {
      drawLine(x1, y1, x2, y2, size, color, pressure)
    } else if (scatter < 0.3) {
      drawLine(x1, y1, x2, y2, size, color, pressure * (1 - scatter))
      const segLen = Math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)
      const steps = Math.max(1, Math.floor(segLen / (0.5 * size)))
      for (let i = 0; i <= steps; i++) {
        const t = steps === 0 ? 0 : i / steps
        drawScatter(
          x1 + (x2 - x1) * t, y1 + (y2 - y1) * t,
          size * scatter,
          Math.floor(density * scatter * 0.3),
          color, pressure * scatter
        )
      }
    } else {
      // full scatter along segment
      const segLen = Math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)
      const steps = Math.max(1, Math.floor(segLen / (0.3 * size)))
      for (let i = 0; i <= steps; i++) {
        const t = steps === 0 ? 0 : i / steps
        drawScatter(
          x1 + (x2 - x1) * t, y1 + (y2 - y1) * t,
          size,
          Math.floor(density * pressure),
          color, 0.7 * pressure
        )
      }
    }
  }

  /** Erase a circle at a point — 'g' function */
  function eraseCircle(x, y, radius) {
    ctx.save()
    ctx.beginPath()
    ctx.arc(x, y, radius, 0, 2 * Math.PI)
    ctx.clip()
    ctx.clearRect(x - radius, y - radius, 2 * radius, 2 * radius)
    ctx.restore()
  }

  /** Erase along a segment — 'M' function */
  function eraseSegment(x1, y1, x2, y2, radius) {
    const segLen = Math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)
    const steps = Math.max(1, Math.floor(segLen / (0.3 * radius)))
    for (let i = 0; i <= steps; i++) {
      const t = steps === 0 ? 0 : i / steps
      eraseCircle(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, radius)
    }
  }

  /** Replay a full recorded stroke — 'm' function */
  function replayStroke(stroke) {
    if (!stroke || !stroke.points || stroke.points.length === 0) return
    const pts = stroke.points
    const scatter = stroke.scatter !== undefined ? stroke.scatter : 1
    if (stroke.type === 'erase') {
      eraseCircle(pts[0].x, pts[0].y, stroke.size)
      for (let i = 1; i < pts.length; i++) {
        eraseSegment(pts[i - 1].x, pts[i - 1].y, pts[i].x, pts[i].y, stroke.size)
      }
    } else {
      renderSprayDot(pts[0].x, pts[0].y, stroke.size, stroke.density, stroke.color, stroke.pressure, scatter)
      for (let i = 1; i < pts.length; i++) {
        renderSpraySegment(
          pts[i - 1].x, pts[i - 1].y, pts[i].x, pts[i].y,
          stroke.size, stroke.density, stroke.color, stroke.pressure, scatter
        )
      }
    }
  }

  // ─── Message handler ──────────────────────────────────────────────────
  window.addEventListener('message', function (event) {
    let data = event.data
    if (typeof data === 'string') {
      try { data = JSON.parse(data) } catch (_) { return }
    }
    if (!data || !data.action) return

    switch (data.action) {

      // ── init ─────────────────────────────────────────────────────────
      case 'init': {
        canvasW = data.width || 1024
        canvasH = data.height || 1024
        canvas.width = canvasW
        canvas.height = canvasH
        ctx.clearRect(0, 0, canvasW, canvasH)
        // Create offscreen scratch canvas (matches original, though unused)
        offscreen = document.createElement('canvas')
        offscreen.width = canvasW
        offscreen.height = canvasH
        offscreen.getContext('2d')
        // Reset state
        strokes = []
        redoStack = []
        snapshots = []
        activeStroke = null
        isDrawing = false
        takeSnapshot()
        break
      }

      // ── startStroke ──────────────────────────────────────────────────
      case 'startStroke': {
        isDrawing = true
        redoStack = []
        activeStroke = {
          type: data.type || 'paint',
          color: data.color || '#000000',
          size: data.size || 10,
          density: data.density || 25,
          pressure: data.pressure || 0.8,
          scatter: data.scatter !== undefined ? data.scatter : 1,
          points: [{ x: data.x, y: data.y }],
        }
        if (activeStroke.type === 'erase') {
          eraseCircle(data.x, data.y, activeStroke.size)
        } else {
          renderSprayDot(
            data.x, data.y,
            activeStroke.size, activeStroke.density,
            activeStroke.color, activeStroke.pressure,
            activeStroke.scatter
          )
        }
        break
      }

      // ── addPoint ─────────────────────────────────────────────────────
      case 'addPoint': {
        if (!isDrawing || !activeStroke) break
        const prev = activeStroke.points[activeStroke.points.length - 1]
        const point = { x: data.x, y: data.y }
        if (data.pressure !== undefined) activeStroke.pressure = data.pressure
        if (data.size !== undefined) activeStroke.size = data.size
        if (data.density !== undefined) activeStroke.density = data.density
        if (data.scatter !== undefined) activeStroke.scatter = data.scatter
        activeStroke.points.push(point)
        if (activeStroke.type === 'erase') {
          eraseSegment(prev.x, prev.y, point.x, point.y, activeStroke.size)
        } else {
          renderSpraySegment(
            prev.x, prev.y, point.x, point.y,
            activeStroke.size, activeStroke.density,
            activeStroke.color, activeStroke.pressure,
            activeStroke.scatter
          )
        }
        break
      }

      // ── endStroke ────────────────────────────────────────────────────
      case 'endStroke': {
        if (isDrawing && activeStroke) {
          isDrawing = false
          strokes.push(activeStroke)
          activeStroke = null
          takeSnapshot()
        }
        break
      }

      // ── undo ─────────────────────────────────────────────────────────
      case 'undo': {
        if (strokes.length === 0) break
        const undone = strokes.pop()
        redoStack.push(undone)
        // Restore previous snapshot (original pops the snapshot too)
        if (snapshots.length > 1) {
          snapshots.pop()
          const idx = snapshots.length - 1
          if (idx >= 0) ctx.putImageData(snapshots[idx], 0, 0)
        } else {
          ctx.clearRect(0, 0, canvasW, canvasH)
        }
        break
      }

      // ── redo ─────────────────────────────────────────────────────────
      case 'redo': {
        if (redoStack.length === 0) break
        const redone = redoStack.pop()
        strokes.push(redone)
        replayStroke(redone)
        takeSnapshot()
        break
      }

      // ── loadStrokes ──────────────────────────────────────────────────
      case 'loadStrokes': {
        ctx.clearRect(0, 0, canvasW, canvasH)
        snapshots = []
        strokes = []
        redoStack = []
        takeSnapshot()
        const incoming = data.strokes || []
        for (let i = 0; i < incoming.length; i++) {
          replayStroke(incoming[i])
          strokes.push(incoming[i])
          takeSnapshot()
        }
        break
      }

      // ── clear ────────────────────────────────────────────────────────
      case 'clear': {
        ctx.clearRect(0, 0, canvasW, canvasH)
        strokes = []
        redoStack = []
        snapshots = []
        activeStroke = null
        isDrawing = false
        takeSnapshot()
        break
      }

      // ── fullRedraw ───────────────────────────────────────────────────
      case 'fullRedraw': {
        ctx.clearRect(0, 0, canvasW, canvasH)
        snapshots = []
        takeSnapshot()
        for (let i = 0; i < strokes.length; i++) {
          replayStroke(strokes[i])
          takeSnapshot()
        }
        break
      }

      // ── getScreenshot ────────────────────────────────────────────────
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

      // ── updateBrush ──────────────────────────────────────────────────
      case 'updateBrush': {
        if (activeStroke) {
          if (data.size !== undefined) activeStroke.size = data.size
          if (data.density !== undefined) activeStroke.density = data.density
          if (data.color !== undefined) activeStroke.color = data.color
          if (data.pressure !== undefined) activeStroke.pressure = data.pressure
          if (data.scatter !== undefined) activeStroke.scatter = data.scatter
        }
        break
      }
    }
  })

  // Initialise canvas on load
  canvas.width = canvasW
  canvas.height = canvasH
  ctx.clearRect(0, 0, canvasW, canvasH)
})()
