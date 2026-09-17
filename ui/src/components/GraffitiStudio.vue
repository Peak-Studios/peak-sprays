<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import {
  studioState,
  showStudio,
  getActiveLayer,
  selectLayer,
  addTextLayer,
  addFreehandLayer,
  addImageLayer,
  addStencilLayer,
  reorderLayer,
  toggleLayerVisibility,
  toggleLayerLock,
  duplicateLayer,
  deleteLayer,
  updateLayerProperty,
  executeTransaction,
  undoStudio,
  redoStudio,
  openDesign,
  newComposition,
  addFreehandStroke,
} from '@/store/studioState'
import { renderComposition, STENCILS } from '@/renderer'
import { fetchNui } from '@/utils/fetchNui'
import type {
  BrushStyleId,
  TextLayer,
  ImageLayer,
  StencilLayer,
  FreehandLayer,
  FreehandStroke,
  GraffitiComposition,
  GraffitiLayer,
} from '@/types/graffiti'

const canvasRef = ref<HTMLCanvasElement | null>(null)
const previewCanvasRef = ref<HTMLCanvasElement | null>(null)
const isDrawing = ref(false)
const currentStrokePoints = ref<{ x: number; y: number; pressure: number }[]>([])

// Direct manipulation transform state
type TransformMode = 'move' | 'rotate' | 'nw' | 'n' | 'ne' | 'e' | 'se' | 's' | 'sw' | 'w' | null
const activeTransformMode = ref<TransformMode>(null)
const transformStartMouse = ref<{ x: number; y: number }>({ x: 0, y: 0 })
const transformStartLayerPos = ref<{ x: number; y: number }>({ x: 0, y: 0 })
const transformStartRotation = ref(0)
const transformStartAngle = ref(0)
const transformStartDistance = ref(0)
const transformStartDims = ref<{ width: number; height: number; fontSize: number; size: number }>({
  width: 256,
  height: 256,
  fontSize: 72,
  size: 70,
})

const FONTS = [
  'Rock Salt',
  'Creepster',
  'Nosifer',
  'Lobster',
  'Oswald',
  'Geist',
  'Montserrat',
  'Lato',
  'Raleway',
]

const BRUSH_STYLES: { id: BrushStyleId; label: string; desc: string }[] = [
  { id: 'spray', label: 'Aerosol Spray', desc: 'Standard can with soft falloff' },
  { id: 'rough_spray', label: 'Rough Spray', desc: 'High-pressure splatter bursts' },
  { id: 'chalk', label: 'Sidewalk Chalk', desc: 'Gritty, porous powder grain' },
  { id: 'crayon', label: 'Street Crayon', desc: 'Waxy core with toothy edges' },
  { id: 'marker_bleed', label: 'Marker Bleed', desc: 'Fat wet chisel ink feather' },
  { id: 'stipple', label: 'Stipple Dots', desc: 'Fine dot matrix scatter' },
  { id: 'roller', label: 'Paint Roller', desc: 'Wide track with edge ridges' },
  { id: 'scratched', label: 'Scratched Paint', desc: 'Etched metal razor grooves' },
  { id: 'pen', label: 'Fine Pen', desc: 'Crisp chisel line' },
  { id: 'calligraphy', label: 'Calligraphy', desc: 'Angle-dynamic ribbon chisel' },
  { id: 'splatter', label: 'Splatter Bomb', desc: 'Impact paint drips and burst' },
  { id: 'airbrush', label: 'Soft Airbrush', desc: 'Ultra-smooth gradient fade' },
  { id: 'drip', label: 'Drip Run', desc: 'Dense paint running down wall' },
]

const COLOR_PRESETS = [
  '#D6FF62', '#FFFFFF', '#000000', '#EF4444', '#F97316',
  '#FBBF24', '#10B981', '#06B6D4', '#3B82F6', '#8B5CF6',
  '#EC4899', '#A855F7', '#64748B', '#78350F',
]

const RESIZE_HANDLES = [
  { id: 'nw' as const, calcX: (hw: number) => -hw, calcY: (hh: number) => -hh, cursor: 'cursor-nwse-resize' },
  { id: 'n' as const,  calcX: (_: number) => 0,   calcY: (hh: number) => -hh, cursor: 'cursor-ns-resize' },
  { id: 'ne' as const, calcX: (hw: number) => hw,  calcY: (hh: number) => -hh, cursor: 'cursor-nesw-resize' },
  { id: 'e' as const,  calcX: (hw: number) => hw,  calcY: (_: number) => 0,   cursor: 'cursor-ew-resize' },
  { id: 'se' as const, calcX: (hw: number) => hw,  calcY: (hh: number) => hh,  cursor: 'cursor-nwse-resize' },
  { id: 's' as const,  calcX: (_: number) => 0,   calcY: (hh: number) => hh,  cursor: 'cursor-ns-resize' },
  { id: 'sw' as const, calcX: (hw: number) => -hw, calcY: (hh: number) => hh,  cursor: 'cursor-nesw-resize' },
  { id: 'w' as const,  calcX: (hw: number) => -hw, calcY: (_: number) => 0,   cursor: 'cursor-ew-resize' },
]

const activeLayer = computed(() => getActiveLayer())

const displayedDesigns = computed(() => {
  switch (studioState.activeLibraryTab) {
    case 'saved':
      return studioState.library.saved || []
    case 'drafts':
      return studioState.library.drafts || []
    case 'templates':
      return studioState.library.templates || []
    case 'gang':
      return studioState.library.gang || []
    case 'recent':
    default:
      return studioState.library.recent || []
  }
})

// Computes 2D bounding box and rotation of the active layer for direct canvas manipulation
const activeLayerBounds = computed(() => {
  const layer = activeLayer.value
  if (!layer) return null

  if (layer.type === 'text') {
    const tl = layer as TextLayer
    const lines = (tl.text || '').split('\n')
    const maxLineLen = lines.reduce((max, l) => Math.max(max, l.length), 1)
    const fontSize = tl.fontSize || 72
    const scale = tl.scale || 1.0
    const letterSpacing = tl.letterSpacing || 0
    const lineHeight = tl.lineHeight || 1.1

    const width = Math.max(60, maxLineLen * fontSize * 0.65 * scale + letterSpacing * maxLineLen + 24)
    const height = Math.max(40, lines.length * fontSize * lineHeight * scale + 16)
    return {
      x: tl.x,
      y: tl.y,
      hw: width / 2,
      hh: height / 2,
      rotation: tl.rotation || 0,
    }
  }

  if (layer.type === 'image') {
    const il = layer as ImageLayer
    const w = il.width || 256
    const h = il.height || 256
    return {
      x: il.x,
      y: il.y,
      hw: w / 2,
      hh: h / 2,
      rotation: il.rotation || 0,
    }
  }

  if (layer.type === 'stencil') {
    const sl = layer as StencilLayer
    const size = sl.size || 70
    const side = size * 2.2
    return {
      x: sl.x,
      y: sl.y,
      hw: side / 2,
      hh: side / 2,
      rotation: sl.rotation || 0,
    }
  }

  if (layer.type === 'freehand') {
    const fl = layer as FreehandLayer
    if (!fl.strokes || fl.strokes.length === 0) return null
    let minX = Infinity
    let maxX = -Infinity
    let minY = Infinity
    let maxY = -Infinity
    let hasPoints = false

    for (const stroke of fl.strokes) {
      if (stroke.points) {
        for (const pt of stroke.points) {
          hasPoints = true
          if (pt.x < minX) minX = pt.x
          if (pt.x > maxX) maxX = pt.x
          if (pt.y < minY) minY = pt.y
          if (pt.y > maxY) maxY = pt.y
        }
      }
    }

    if (!hasPoints) return null
    const pad = 20
    const width = Math.max(40, maxX - minX + pad * 2)
    const height = Math.max(40, maxY - minY + pad * 2)
    return {
      x: (minX + maxX) / 2,
      y: (minY + maxY) / 2,
      hw: width / 2,
      hh: height / 2,
      rotation: 0,
    }
  }

  return null
})

// Re-render editor canvas whenever composition updates
async function triggerRender() {
  if (canvasRef.value) {
    const ctx = canvasRef.value.getContext('2d')
    if (ctx) {
      await renderComposition(ctx, studioState.composition, { clear: true })
    }
  }
  if (previewCanvasRef.value) {
    const pctx = previewCanvasRef.value.getContext('2d')
    if (pctx) {
      await renderComposition(pctx, studioState.composition, { clear: true })
    }
  }
}

watch(
  () => [
    studioState.composition,
    studioState.composition.layers,
    studioState.activeStep,
    studioState.preview,
  ],
  () => {
    triggerRender()
  },
  { deep: true }
)

// ─── Canvas Coordinate Mapping & Hit Testing ───────────────────────────

function getCanvasCoords(e: MouseEvent | PointerEvent): { x: number; y: number } {
  if (!canvasRef.value) return { x: 0, y: 0 }
  const rect = canvasRef.value.getBoundingClientRect()
  const scaleX = canvasRef.value.width / rect.width
  const scaleY = canvasRef.value.height / rect.height
  return {
    x: (e.clientX - rect.left) * scaleX,
    y: (e.clientY - rect.top) * scaleY,
  }
}

function hitTestLayer(layer: GraffitiLayer, px: number, py: number): boolean {
  if (!layer.visible) return false

  if (layer.type === 'text') {
    const tl = layer as TextLayer
    const lines = (tl.text || '').split('\n')
    const maxLineLen = lines.reduce((max, l) => Math.max(max, l.length), 1)
    const fontSize = tl.fontSize || 72
    const hw = Math.max(30, (maxLineLen * fontSize * 0.65) / 2 + 15)
    const hh = Math.max(20, (lines.length * fontSize * 1.1) / 2 + 10)

    const rad = -((tl.rotation || 0) * Math.PI) / 180
    const dx = px - tl.x
    const dy = py - tl.y
    const lx = dx * Math.cos(rad) - dy * Math.sin(rad)
    const ly = dx * Math.sin(rad) + dy * Math.cos(rad)
    return Math.abs(lx) <= hw && Math.abs(ly) <= hh
  }

  if (layer.type === 'image') {
    const il = layer as ImageLayer
    const hw = (il.width || 256) / 2
    const hh = (il.height || 256) / 2

    const rad = -((il.rotation || 0) * Math.PI) / 180
    const dx = px - il.x
    const dy = py - il.y
    const lx = dx * Math.cos(rad) - dy * Math.sin(rad)
    const ly = dx * Math.sin(rad) + dy * Math.cos(rad)
    return Math.abs(lx) <= hw && Math.abs(ly) <= hh
  }

  if (layer.type === 'stencil') {
    const sl = layer as StencilLayer
    const r = (sl.size || 70) * 1.1

    const rad = -((sl.rotation || 0) * Math.PI) / 180
    const dx = px - sl.x
    const dy = py - sl.y
    const lx = dx * Math.cos(rad) - dy * Math.sin(rad)
    const ly = dx * Math.sin(rad) + dy * Math.cos(rad)
    return Math.abs(lx) <= r && Math.abs(ly) <= r
  }

  if (layer.type === 'freehand') {
    const fl = layer as FreehandLayer
    for (const stroke of fl.strokes || []) {
      for (const pt of stroke.points || []) {
        const dist = Math.hypot(px - pt.x, py - pt.y)
        if (dist <= (stroke.size || 14) / 2 + 8) return true
      }
    }
  }

  return false
}

// ─── Freehand Canvas Drawing ───────────────────────────────────────────

function onCanvasMouseDown(e: MouseEvent) {
  const coords = getCanvasCoords(e)

  // If select tool is active or not drawing, check for layer selection
  if (studioState.activeTool === 'select') {
    const layers = [...studioState.composition.layers].reverse()
    for (const l of layers) {
      if (hitTestLayer(l, coords.x, coords.y)) {
        selectLayer(l.id)
        return
      }
    }
    return
  }

  if (studioState.activeTool !== 'brush') return

  // Ensure active layer is an unlocked freehand layer
  let layer = activeLayer.value
  if (!layer || layer.type !== 'freehand' || layer.locked) {
    addFreehandLayer('Spray Paint Layer', studioState.brush.style)
    layer = activeLayer.value as FreehandLayer
  }

  isDrawing.value = true
  currentStrokePoints.value = [{ x: coords.x, y: coords.y, pressure: studioState.brush.pressure }]

  const fh = layer as FreehandLayer
  const newStroke: FreehandStroke = {
    type: 'paint',
    style: studioState.brush.style,
    color: studioState.brush.color,
    size: studioState.brush.size,
    density: Math.floor(studioState.brush.density * 30),
    pressure: studioState.brush.pressure,
    scatter: studioState.brush.scatter,
    points: currentStrokePoints.value,
  }

  addFreehandStroke(fh.id, newStroke)
  triggerRender()
}

function onCanvasMouseMove(e: MouseEvent) {
  if (!isDrawing.value || studioState.activeTool !== 'brush') return
  const coords = getCanvasCoords(e)
  currentStrokePoints.value.push({ x: coords.x, y: coords.y, pressure: studioState.brush.pressure })
  triggerRender()
}

function onCanvasMouseUp() {
  if (isDrawing.value) {
    isDrawing.value = false
    currentStrokePoints.value = []
  }
}

// ─── Direct Manipulation: Move, Resize & Rotate ───────────────────────

function onBoxPointerDown(e: PointerEvent) {
  const layer = activeLayer.value
  if (!layer || layer.locked) return

  ;(e.target as HTMLElement).setPointerCapture(e.pointerId)
  activeTransformMode.value = 'move'
  const coords = getCanvasCoords(e)
  transformStartMouse.value = { x: coords.x, y: coords.y }

  if ('x' in layer && 'y' in layer) {
    transformStartLayerPos.value = { x: (layer as any).x, y: (layer as any).y }
  } else if (activeLayerBounds.value) {
    transformStartLayerPos.value = { x: activeLayerBounds.value.x, y: activeLayerBounds.value.y }
  }
}

function onRotateHandlePointerDown(e: PointerEvent) {
  const layer = activeLayer.value
  if (!layer || layer.locked) return

  ;(e.target as HTMLElement).setPointerCapture(e.pointerId)
  activeTransformMode.value = 'rotate'
  const coords = getCanvasCoords(e)
  const bounds = activeLayerBounds.value
  if (!bounds) return

  transformStartRotation.value = (layer as any).rotation || 0
  transformStartAngle.value = Math.atan2(coords.y - bounds.y, coords.x - bounds.x) * (180 / Math.PI)
}

function onResizeHandlePointerDown(e: PointerEvent, handleId: TransformMode) {
  const layer = activeLayer.value
  if (!layer || layer.locked) return

  ;(e.target as HTMLElement).setPointerCapture(e.pointerId)
  activeTransformMode.value = handleId
  const coords = getCanvasCoords(e)
  const bounds = activeLayerBounds.value
  if (!bounds) return

  transformStartDistance.value = Math.hypot(coords.x - bounds.x, coords.y - bounds.y)
  transformStartDims.value = {
    width: (layer as any).width || 256,
    height: (layer as any).height || 256,
    fontSize: (layer as any).fontSize || 72,
    size: (layer as any).size || 70,
  }
}

function onOverlayPointerMove(e: PointerEvent) {
  if (!activeTransformMode.value) return
  const layer = activeLayer.value
  if (!layer || layer.locked) return

  const coords = getCanvasCoords(e)

  if (activeTransformMode.value === 'move') {
    const dx = coords.x - transformStartMouse.value.x
    const dy = coords.y - transformStartMouse.value.y

    if ('x' in layer && 'y' in layer) {
      ;(layer as any).x = Math.round(transformStartLayerPos.value.x + dx)
      ;(layer as any).y = Math.round(transformStartLayerPos.value.y + dy)
      triggerRender()
    }
  } else if (activeTransformMode.value === 'rotate') {
    const bounds = activeLayerBounds.value
    if (!bounds) return

    const curAngle = Math.atan2(coords.y - bounds.y, coords.x - bounds.x) * (180 / Math.PI)
    const delta = curAngle - transformStartAngle.value
    let newRot = Math.round(transformStartRotation.value + delta)
    if (e.shiftKey || studioState.placement.snapRotation) {
      newRot = Math.round(newRot / 15) * 15
    }
    newRot = ((newRot % 360) + 360) % 360
    ;(layer as any).rotation = newRot
    triggerRender()
  } else {
    // Resize handles
    const bounds = activeLayerBounds.value
    if (!bounds) return

    const curDist = Math.hypot(coords.x - bounds.x, coords.y - bounds.y)
    const factor = Math.max(0.2, curDist / (transformStartDistance.value || 1))

    if (layer.type === 'image') {
      const il = layer as ImageLayer
      il.width = Math.max(40, Math.min(1024, Math.round(transformStartDims.value.width * factor)))
      il.height = Math.max(40, Math.min(1024, Math.round(transformStartDims.value.height * factor)))
      triggerRender()
    } else if (layer.type === 'text') {
      const tl = layer as TextLayer
      tl.fontSize = Math.max(16, Math.min(200, Math.round(transformStartDims.value.fontSize * factor)))
      triggerRender()
    } else if (layer.type === 'stencil') {
      const sl = layer as StencilLayer
      sl.size = Math.max(10, Math.min(300, Math.round(transformStartDims.value.size * factor)))
      triggerRender()
    }
  }
}

function onOverlayPointerUp() {
  if (!activeTransformMode.value) return
  const mode = activeTransformMode.value
  activeTransformMode.value = null
  const layer = activeLayer.value
  if (!layer || layer.locked) return

  // Register undoable transaction for the completed transformation
  if (mode === 'move' && 'x' in layer && 'y' in layer) {
    const beforeX = transformStartLayerPos.value.x
    const beforeY = transformStartLayerPos.value.y
    const afterX = (layer as any).x
    const afterY = (layer as any).y
    const id = layer.id

    executeTransaction({
      description: `Move ${layer.name}`,
      estimatedBytes: 64,
      apply: () => {
        const l = studioState.composition.layers.find((i) => i.id === id)
        if (l && !l.locked && 'x' in l && 'y' in l) {
          ;(l as any).x = afterX
          ;(l as any).y = afterY
          return true
        }
        return false
      },
      undo: () => {
        const l = studioState.composition.layers.find((i) => i.id === id)
        if (l && !l.locked && 'x' in l && 'y' in l) {
          ;(l as any).x = beforeX
          ;(l as any).y = beforeY
        }
      },
    })
  } else if (mode === 'rotate' && 'rotation' in layer) {
    const beforeRot = transformStartRotation.value
    const afterRot = (layer as any).rotation
    const id = layer.id

    executeTransaction({
      description: `Rotate ${layer.name}`,
      estimatedBytes: 64,
      apply: () => {
        const l = studioState.composition.layers.find((i) => i.id === id)
        if (l && !l.locked && 'rotation' in l) {
          ;(l as any).rotation = afterRot
          return true
        }
        return false
      },
      undo: () => {
        const l = studioState.composition.layers.find((i) => i.id === id)
        if (l && !l.locked && 'rotation' in l) {
          ;(l as any).rotation = beforeRot
        }
      },
    })
  }
}

// ─── Keyboard Shortcuts & Nudging ──────────────────────────────────────

function handleKeyDown(e: KeyboardEvent) {
  if (!showStudio.value) return

  // Skip shortcuts if currently typing in an input or textarea
  const activeEl = document.activeElement
  if (
    activeEl &&
    (activeEl.tagName === 'INPUT' ||
      activeEl.tagName === 'TEXTAREA' ||
      (activeEl as HTMLElement).isContentEditable)
  ) {
    return
  }

  // Undo / Redo
  if (e.ctrlKey || e.metaKey) {
    if (e.key === 'z' || e.key === 'Z') {
      e.preventDefault()
      if (e.shiftKey) redoStudio()
      else undoStudio()
      return
    } else if (e.key === 'y' || e.key === 'Y') {
      e.preventDefault()
      redoStudio()
      return
    }
  }

  // Delete / Backspace
  if (e.key === 'Delete' || e.key === 'Backspace') {
    if (activeLayer.value && !activeLayer.value.locked) {
      e.preventDefault()
      deleteLayer(activeLayer.value.id)
    }
    return
  }

  // Arrow Keys Nudging
  if (
    e.key === 'ArrowUp' ||
    e.key === 'ArrowDown' ||
    e.key === 'ArrowLeft' ||
    e.key === 'ArrowRight'
  ) {
    const layer = activeLayer.value
    if (!layer || layer.locked) return

    e.preventDefault()
    const step = e.shiftKey ? 10 : 1
    let dx = 0
    let dy = 0
    if (e.key === 'ArrowLeft') dx = -step
    if (e.key === 'ArrowRight') dx = step
    if (e.key === 'ArrowUp') dy = -step
    if (e.key === 'ArrowDown') dy = step

    if ('x' in layer && 'y' in layer) {
      const startX = (layer as any).x
      const startY = (layer as any).y
      const endX = startX + dx
      const endY = startY + dy
      const id = layer.id

      executeTransaction({
        description: `Nudge ${layer.name}`,
        estimatedBytes: 64,
        apply: () => {
          const l = studioState.composition.layers.find((i) => i.id === id)
          if (l && !l.locked && 'x' in l && 'y' in l) {
            ;(l as any).x = endX
            ;(l as any).y = endY
            return true
          }
          return false
        },
        undo: () => {
          const l = studioState.composition.layers.find((i) => i.id === id)
          if (l && !l.locked && 'x' in l && 'y' in l) {
            ;(l as any).x = startX
            ;(l as any).y = startY
          }
        },
      })
      triggerRender()
    }
  }
}

// ─── Clipboard Paste for Image Importing ───────────────────────────────

function handlePaste(e: ClipboardEvent) {
  if (!showStudio.value) return
  const items = e.clipboardData?.items
  if (!items) return

  for (let i = 0; i < items.length; i++) {
    const item = items[i]
    if (item.type.indexOf('image') !== -1) {
      const blob = item.getAsFile()
      if (blob) {
        const reader = new FileReader()
        reader.onload = (event) => {
          const dataUrl = event.target?.result as string
          if (dataUrl) {
            studioState.imageModal.dataUrl = dataUrl
            studioState.imageModal.url = ''
            studioState.imageModal.visible = true
          }
        }
        reader.readAsDataURL(blob)
      }
      break
    } else if (item.type === 'text/plain') {
      item.getAsString((text) => {
        if (text.startsWith('http://') || text.startsWith('https://')) {
          studioState.imageModal.url = text
          studioState.imageModal.dataUrl = ''
          studioState.imageModal.visible = true
        }
      })
    }
  }
}

// ─── Drag & Drop for Image Importing ───────────────────────────────────

function onDrop(e: DragEvent) {
  e.preventDefault()
  if (!e.dataTransfer) return
  const files = e.dataTransfer.files
  if (files.length > 0 && files[0].type.startsWith('image/')) {
    const reader = new FileReader()
    reader.onload = (event) => {
      const dataUrl = event.target?.result as string
      if (dataUrl) {
        studioState.imageModal.dataUrl = dataUrl
        studioState.imageModal.url = ''
        studioState.imageModal.visible = true
      }
    }
    reader.readAsDataURL(files[0])
  }
}

function onDragOver(e: DragEvent) {
  e.preventDefault()
}

// ─── Server & NUI Actions ──────────────────────────────────────────────

async function loadDesignsLibrary() {
  const lib = await fetchNui('getDesignsLibrary')
  if (lib) {
    studioState.library = lib
    if (lib.playerIdentifier) {
      studioState.playerIdentifier = lib.playerIdentifier
    }
  }
}

async function saveCurrentDesign(category: 'saved' | 'draft' = 'saved', variant = 'default') {
  let thumbnail: string | undefined = undefined
  if (canvasRef.value) {
    thumbnail = canvasRef.value.toDataURL('image/jpeg', 0.6)
  }

  const isUpdatingOwned =
    studioState.activeRecordId !== null &&
    studioState.activeRecordMetadata?.isOwner === true

  const payload = {
    id: isUpdatingOwned ? studioState.activeRecordId : undefined,
    title: studioState.composition.title || 'Untitled Tag',
    category,
    variant,
    composition: studioState.composition,
    thumbnail,
  }

  const res = await fetchNui('saveDesign', payload)
  if (res && res.success) {
    studioState.activeRecordId = res.id
    studioState.activeRecordMetadata = {
      id: res.id,
      category,
      variant,
      isOwner: true,
      isServerTemplate: false,
    }
    studioState.isDirty = false
    fetchNui('notify', {
      text: isUpdatingOwned ? 'Design updated in library!' : 'Design saved to library!',
      type: 'success',
    })
    await loadDesignsLibrary()
  } else {
    fetchNui('notify', { text: res?.message || 'Failed to save design', type: 'error' })
  }
}

function handleOpenDesign(design: any) {
  const res = openDesign(design)
  if (res.success) {
    studioState.activeStep = 'studio'
  } else {
    fetchNui('notify', { text: res.message || 'Failed to open design', type: 'error' })
  }
}

function handleQuickPlace(design: any) {
  const res = openDesign(design)
  if (res.success) {
    startPlacement()
  } else {
    fetchNui('notify', { text: res.message || 'Failed to open design', type: 'error' })
  }
}

function canDeleteDesign(design: any): boolean {
  if (design.isServerTemplate || design.category === 'template') return false
  const currentPid = studioState.playerIdentifier || studioState.library?.playerIdentifier
  return Boolean(currentPid && design.identifier === currentPid)
}

async function handleDeleteDesign(id: number) {
  const res = await fetchNui('deleteDesign', { id })
  if (res && res.success) {
    fetchNui('notify', { text: 'Design deleted', type: 'info' })
    await loadDesignsLibrary()
  } else {
    fetchNui('notify', { text: res?.message || 'Failed to delete design', type: 'error' })
  }
}

async function publishGangOfficial() {
  if (!studioState.gangModal.title) studioState.gangModal.title = studioState.composition.title

  let thumbnail: string | undefined = undefined
  if (canvasRef.value) {
    thumbnail = canvasRef.value.toDataURL('image/jpeg', 0.6)
  }

  const res = await fetchNui('publishGangTemplate', {
    title: studioState.gangModal.title,
    variant: studioState.gangModal.variant,
    composition: studioState.composition,
    thumbnail,
  })

  if (res && res.success) {
    fetchNui('notify', { text: 'Official crew template published!', type: 'success' })
    studioState.gangModal.visible = false
    await loadDesignsLibrary()
  } else {
    fetchNui('notify', { text: res?.message || 'Failed to publish crew template', type: 'error' })
  }
}

function startPlacement() {
  showStudio.value = false
  fetchNui('startDesignPlacement', {
    composition: studioState.composition,
    presetSize: studioState.placement.presetSize,
    duplicateMode: studioState.placement.duplicateMode,
  })
}

function closeStudio() {
  showStudio.value = false
  fetchNui('closeStudio')
}

// ─── JSON Export / Import ──────────────────────────────────────────────

function openExportModal() {
  studioState.jsonModal.mode = 'export'
  studioState.jsonModal.content = JSON.stringify(
    {
      peak_spray_format: 'v1',
      title: studioState.composition.title,
      composition: studioState.composition,
    },
    null,
    2
  )
  studioState.jsonModal.copied = false
  studioState.jsonModal.error = ''
  studioState.jsonModal.visible = true
}

function openImportModal() {
  studioState.jsonModal.mode = 'import'
  studioState.jsonModal.content = ''
  studioState.jsonModal.copied = false
  studioState.jsonModal.error = ''
  studioState.jsonModal.visible = true
}

function copyJsonToClipboard() {
  navigator.clipboard.writeText(studioState.jsonModal.content).then(() => {
    studioState.jsonModal.copied = true
    setTimeout(() => {
      studioState.jsonModal.copied = false
    }, 2000)
  })
}

function executeImportJson() {
  try {
    const parsed = JSON.parse(studioState.jsonModal.content)
    const comp = parsed.composition || parsed
    const res = openDesign({ composition: comp, title: comp.title || 'Imported Tag' })
    if (!res.success) {
      studioState.jsonModal.error = res.message || 'Invalid Peak Spray design JSON format.'
      return
    }
    studioState.jsonModal.visible = false
    studioState.activeStep = 'studio'
    fetchNui('notify', { text: 'Design imported successfully!', type: 'success' })
  } catch (err: any) {
    studioState.jsonModal.error = 'JSON syntax error: ' + err.message
  }
}

function confirmImageImport() {
  addImageLayer(
    studioState.imageModal.url,
    studioState.imageModal.dataUrl,
    {
      brightness: studioState.imageModal.brightness,
      contrast: studioState.imageModal.contrast,
      monochrome: studioState.imageModal.monochrome,
      blur: studioState.imageModal.blur,
      removeBg: studioState.imageModal.removeBg,
      removeBgThreshold: studioState.imageModal.removeBgThreshold,
    }
  )
  studioState.imageModal.visible = false
  studioState.imageModal.url = ''
  studioState.imageModal.dataUrl = ''
}

// ─── Lifecycle & Listeners ─────────────────────────────────────────────

onMounted(() => {
  window.addEventListener('paste', handlePaste)
  window.addEventListener('keydown', handleKeyDown)
  loadDesignsLibrary()
  setTimeout(triggerRender, 100)
})

onUnmounted(() => {
  window.removeEventListener('paste', handlePaste)
  window.removeEventListener('keydown', handleKeyDown)
})
</script>

<template>
  <div
    v-if="showStudio"
    class="fixed inset-0 z-[200] flex flex-col bg-neutral-950/90 backdrop-blur-xl text-white select-none font-sans overflow-hidden"
  >
    <!-- ─── Top Studio Header & Step Stepper ────────────────────────────── -->
    <header class="h-16 px-6 border-b border-white/10 flex items-center justify-between bg-black/40">
      <div class="flex items-center gap-4">
        <div class="flex items-center gap-2">
          <span class="w-3 h-3 rounded-full bg-[#D6FF62] shadow-[0_0_12px_#D6FF62]"></span>
          <span class="font-black tracking-widest text-lg uppercase bg-gradient-to-r from-white via-neutral-200 to-[#D6FF62] bg-clip-text text-transparent">
            PEAK GRAFFITI STUDIO
          </span>
          <span class="text-[10px] px-2 py-0.5 rounded bg-[#D6FF62]/20 text-[#D6FF62] font-mono font-bold">
            PRO v1.0
          </span>
        </div>

        <!-- Flow Stepper -->
        <nav class="hidden md:flex items-center gap-1 ml-6 p-1 bg-white/5 rounded-xl border border-white/10 text-xs font-semibold">
          <button
            @click="studioState.activeStep = 'library'"
            :class="[
              'px-4 py-1.5 rounded-lg transition-all',
              studioState.activeStep === 'library'
                ? 'bg-[#D6FF62] text-black shadow font-bold'
                : 'text-neutral-400 hover:text-white',
            ]"
          >
            1. Designs Library
          </button>
          <button
            @click="studioState.activeStep = 'studio'"
            :class="[
              'px-4 py-1.5 rounded-lg transition-all',
              studioState.activeStep === 'studio'
                ? 'bg-[#D6FF62] text-black shadow font-bold'
                : 'text-neutral-400 hover:text-white',
            ]"
          >
            2. Design Editor
          </button>
          <button
            @click="studioState.activeStep = 'preview'"
            :class="[
              'px-4 py-1.5 rounded-lg transition-all',
              studioState.activeStep === 'preview'
                ? 'bg-[#D6FF62] text-black shadow font-bold'
                : 'text-neutral-400 hover:text-white',
            ]"
          >
            3. WYSIWYG Wall Preview
          </button>
          <button
            @click="studioState.activeStep = 'placement'"
            :class="[
              'px-4 py-1.5 rounded-lg transition-all',
              studioState.activeStep === 'placement'
                ? 'bg-[#D6FF62] text-black shadow font-bold'
                : 'text-neutral-400 hover:text-white',
            ]"
          >
            4. Smart Placement
          </button>
        </nav>
      </div>

      <!-- Action Buttons -->
      <div class="flex items-center gap-3">
        <button
          @click="undoStudio"
          class="p-2 rounded-lg bg-white/5 hover:bg-white/10 text-neutral-300 hover:text-white border border-white/10"
          title="Undo (Ctrl+Z)"
        >
          ↺
        </button>
        <button
          @click="redoStudio"
          class="p-2 rounded-lg bg-white/5 hover:bg-white/10 text-neutral-300 hover:text-white border border-white/10"
          title="Redo (Ctrl+Y)"
        >
          ↻
        </button>

        <button
          @click="openExportModal"
          class="px-3 py-1.5 text-xs font-semibold rounded-lg bg-white/5 hover:bg-white/10 border border-white/10 text-neutral-300"
        >
          JSON Export
        </button>
        <button
          @click="openImportModal"
          class="px-3 py-1.5 text-xs font-semibold rounded-lg bg-white/5 hover:bg-white/10 border border-white/10 text-neutral-300"
        >
          JSON Import
        </button>

        <button
          @click="saveCurrentDesign('draft')"
          class="px-3.5 py-1.5 text-xs font-semibold rounded-lg bg-neutral-800 hover:bg-neutral-700 border border-white/10 text-white"
        >
          Save Draft
        </button>

        <button
          @click="saveCurrentDesign('saved')"
          class="px-4 py-1.5 text-xs font-black tracking-wider uppercase rounded-lg bg-[#D6FF62] hover:bg-[#c4ed50] text-black shadow-[0_0_20px_rgba(214,255,98,0.3)] transition-all"
        >
          {{ studioState.activeRecordId ? 'Update Design' : 'Save to Library' }}
        </button>

        <button
          @click="startPlacement"
          class="px-4 py-1.5 text-xs font-black tracking-wider uppercase rounded-lg bg-emerald-500 hover:bg-emerald-400 text-black shadow-[0_0_20px_rgba(16,185,129,0.35)] transition-all"
        >
          Place on Wall
        </button>

        <button
          @click="closeStudio"
          class="w-8 h-8 rounded-lg flex items-center justify-center bg-white/5 hover:bg-rose-500/20 hover:text-rose-400 text-neutral-400 transition-colors"
        >
          ✕
        </button>
      </div>
    </header>

    <!-- ─── Main Content Views ─────────────────────────────────────────── -->

    <!-- VIEW 1: MY DESIGNS LIBRARY -->
    <main v-if="studioState.activeStep === 'library'" class="flex-1 p-8 overflow-y-auto max-w-7xl mx-auto w-full">
      <div class="flex items-center justify-between mb-8">
        <div>
          <h1 class="text-3xl font-black tracking-tight text-white">MY DESIGNS LIBRARY</h1>
          <p class="text-neutral-400 text-sm mt-1">
            Access your saved compositions, drafts, community server templates, and gang tags.
          </p>
        </div>
        <button
          @click="newComposition(); studioState.activeStep = 'studio'"
          class="px-5 py-2.5 rounded-xl bg-[#D6FF62] text-black font-black text-sm tracking-wide flex items-center gap-2 shadow-[0_0_24px_rgba(214,255,98,0.3)] hover:scale-105 transition-all"
        >
          + Create New Tag
        </button>
      </div>

      <!-- Category Filter Tabs -->
      <div class="flex items-center gap-2 border-b border-white/10 pb-4 mb-6 text-sm font-semibold">
        <button
          v-for="cat in [
            { id: 'saved', label: 'Saved Designs', count: (studioState.library.saved || []).length },
            { id: 'drafts', label: 'Drafts', count: (studioState.library.drafts || []).length },
            { id: 'recent', label: 'Recent Tags', count: (studioState.library.recent || []).length },
            { id: 'templates', label: 'Server Templates', count: (studioState.library.templates || []).length },
            { id: 'gang', label: 'Shared Gang Tags', count: (studioState.library.gang || []).length },
          ]"
          :key="cat.id"
          @click="studioState.activeLibraryTab = cat.id as any"
          :class="[
            'px-4 py-2 rounded-xl transition-all flex items-center gap-2',
            studioState.activeLibraryTab === cat.id
              ? 'bg-white/15 text-white border border-white/20'
              : 'text-neutral-400 hover:text-white',
          ]"
        >
          <span>{{ cat.label }}</span>
          <span class="text-xs px-1.5 py-0.5 rounded-full bg-white/10">{{ cat.count }}</span>
        </button>
      </div>

      <!-- Designs Grid -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
        <div
          v-for="design in displayedDesigns"
          :key="design.id"
          class="group rounded-2xl border border-white/10 bg-neutral-900/60 hover:border-[#D6FF62]/50 p-4 transition-all duration-300 hover:shadow-[0_12px_40px_rgba(0,0,0,0.8)] flex flex-col justify-between"
        >
          <div>
            <!-- Thumbnail View -->
            <div class="w-full aspect-square rounded-xl bg-black/60 border border-white/5 relative overflow-hidden flex items-center justify-center p-3">
              <img
                v-if="design.thumbnail"
                :src="design.thumbnail"
                class="w-full h-full object-contain filter drop-shadow-lg"
              />
              <div v-else class="text-neutral-600 font-mono text-xs">
                [No Thumbnail Preview]
              </div>
              <!-- Badge -->
              <span
                class="absolute top-2 left-2 text-[10px] font-bold uppercase tracking-wider px-2 py-0.5 rounded-full bg-black/70 backdrop-blur border border-white/10 text-[#D6FF62]"
              >
                {{ design.variant || design.category || 'tag' }}
              </span>
            </div>

            <div class="mt-4">
              <h3 class="font-bold text-white text-base truncate">{{ design.title }}</h3>
              <p class="text-xs text-neutral-400 mt-0.5">
                {{ design.layerCount || design.composition?.layers?.length || 0 }} Layers • {{ design.playerName || 'Author' }}
              </p>
            </div>
          </div>

          <div class="mt-4 pt-3 border-t border-white/10 flex items-center gap-2">
            <button
              @click="handleOpenDesign(design)"
              class="flex-1 py-2 text-xs font-bold rounded-lg bg-white/10 hover:bg-[#D6FF62] hover:text-black transition-all"
            >
              Open Editor
            </button>
            <button
              @click="handleQuickPlace(design)"
              class="px-3 py-2 text-xs font-bold rounded-lg bg-emerald-500/20 text-emerald-300 hover:bg-emerald-500 hover:text-black transition-all"
              title="Quick Place on Wall"
            >
              Place
            </button>
            <button
              v-if="canDeleteDesign(design)"
              @click="handleDeleteDesign(design.id)"
              class="p-2 text-xs rounded-lg bg-rose-500/10 text-rose-400 hover:bg-rose-500 hover:text-white transition-all"
              title="Delete Design"
            >
              ✕
            </button>
          </div>
        </div>
      </div>
    </main>

    <!-- VIEW 2: LAYERED GRAFFITI STUDIO -->
    <main v-else-if="studioState.activeStep === 'studio'" class="flex-1 flex overflow-hidden">
      <!-- Left Toolbar -->
      <aside class="w-16 border-r border-white/10 bg-black/40 flex flex-col items-center py-4 gap-3">
        <button
          @click="studioState.activeTool = 'select'"
          :class="[
            'w-10 h-10 rounded-xl flex items-center justify-center transition-all font-black text-base',
            studioState.activeTool === 'select'
              ? 'bg-[#D6FF62] text-black shadow-[0_0_15px_#D6FF62]'
              : 'text-neutral-400 hover:text-white hover:bg-white/5',
          ]"
          title="Select & Direct Transform (Pointer / Handles)"
        >
          ↖
        </button>

        <button
          @click="studioState.activeTool = 'brush'"
          :class="[
            'w-10 h-10 rounded-xl flex items-center justify-center transition-all',
            studioState.activeTool === 'brush'
              ? 'bg-[#D6FF62] text-black shadow-[0_0_15px_#D6FF62]'
              : 'text-neutral-400 hover:text-white hover:bg-white/5',
          ]"
          title="Freehand Brush (Textured)"
        >
          🖌️
        </button>

        <button
          @click="addTextLayer(); studioState.activeTool = 'text'"
          :class="[
            'w-10 h-10 rounded-xl flex items-center justify-center transition-all font-black text-lg',
            studioState.activeTool === 'text'
              ? 'bg-[#D6FF62] text-black shadow-[0_0_15px_#D6FF62]'
              : 'text-neutral-400 hover:text-white hover:bg-white/5',
          ]"
          title="Add Text Layer"
        >
          T
        </button>

        <button
          @click="studioState.imageModal.visible = true"
          :class="[
            'w-10 h-10 rounded-xl flex items-center justify-center transition-all',
            studioState.activeTool === 'image'
              ? 'bg-[#D6FF62] text-black shadow-[0_0_15px_#D6FF62]'
              : 'text-neutral-400 hover:text-white hover:bg-white/5',
          ]"
          title="Import Image (Paste / Drag & Drop / URL)"
        >
          🖼️
        </button>

        <button
          @click="addStencilLayer('Peak'); studioState.activeTool = 'stencil'"
          :class="[
            'w-10 h-10 rounded-xl flex items-center justify-center transition-all',
            studioState.activeTool === 'stencil'
              ? 'bg-[#D6FF62] text-black shadow-[0_0_15px_#D6FF62]'
              : 'text-neutral-400 hover:text-white hover:bg-white/5',
          ]"
          title="Stencil Stamps"
        >
          ⭐
        </button>

        <hr class="w-8 border-white/10 my-2" />

        <!-- Gang Template Button -->
        <button
          @click="studioState.gangModal.visible = true"
          class="w-10 h-10 rounded-xl flex items-center justify-center text-amber-400 hover:bg-amber-400/20 border border-amber-400/30"
          title="Publish Official Gang Tag"
        >
          👑
        </button>
      </aside>

      <!-- Center Canvas Work Area -->
      <section
        class="flex-1 bg-neutral-950 relative flex items-center justify-center p-8 overflow-hidden"
        @drop="onDrop"
        @dragover="onDragOver"
      >
        <!-- Canvas Card -->
        <div
          class="relative shadow-[0_25px_80px_rgba(0,0,0,0.9)] rounded-2xl overflow-hidden border border-white/20 max-h-[82vh] aspect-square"
          :style="{
            backgroundColor: studioState.composition.background === 'transparent' ? '#141414' : '#1e1e1e',
            backgroundImage:
              studioState.composition.background === 'transparent'
                ? 'radial-gradient(rgba(255,255,255,0.08) 1px, transparent 1px)'
                : 'none',
            backgroundSize: '24px 24px',
          }"
        >
          <canvas
            ref="canvasRef"
            width="1024"
            height="1024"
            :class="[
              'w-full h-full block',
              studioState.activeTool === 'brush' ? 'cursor-crosshair' : 'cursor-default',
            ]"
            @mousedown="onCanvasMouseDown"
            @mousemove="onCanvasMouseMove"
            @mouseup="onCanvasMouseUp"
            @mouseleave="onCanvasMouseUp"
          />

          <!-- Interactive SVG Transform Overlay (Direct Manipulation) -->
          <svg
            viewBox="0 0 1024 1024"
            class="absolute inset-0 w-full h-full pointer-events-none select-none"
            @pointermove="onOverlayPointerMove"
            @pointerup="onOverlayPointerUp"
          >
            <!-- Unlocked Active Layer: 8 resize handles + rotation handle -->
            <g
              v-if="activeLayer && activeLayerBounds && !activeLayer.locked"
              :transform="`translate(${activeLayerBounds.x}, ${activeLayerBounds.y}) rotate(${activeLayerBounds.rotation})`"
            >
              <!-- Bounding Box -->
              <rect
                :x="-activeLayerBounds.hw"
                :y="-activeLayerBounds.hh"
                :width="activeLayerBounds.hw * 2"
                :height="activeLayerBounds.hh * 2"
                fill="rgba(214,255,98,0.04)"
                stroke="#D6FF62"
                stroke-width="2"
                stroke-dasharray="6 4"
                class="pointer-events-auto cursor-move"
                @pointerdown.stop="onBoxPointerDown"
              />

              <!-- Rotation Stem and Handle -->
              <line
                :x1="0"
                :y1="-activeLayerBounds.hh"
                :x2="0"
                :y2="-activeLayerBounds.hh - 28"
                stroke="#D6FF62"
                stroke-width="2"
              />
              <circle
                :cx="0"
                :cy="-activeLayerBounds.hh - 28"
                r="8"
                fill="#D6FF62"
                stroke="#000000"
                stroke-width="2"
                class="pointer-events-auto cursor-grab hover:scale-125 transition-transform"
                @pointerdown.stop="onRotateHandlePointerDown"
              />

              <!-- 8 Resize Handles -->
              <rect
                v-for="h in RESIZE_HANDLES"
                :key="h.id"
                :x="h.calcX(activeLayerBounds.hw) - 6"
                :y="h.calcY(activeLayerBounds.hh) - 6"
                width="12"
                height="12"
                fill="#FFFFFF"
                stroke="#000000"
                stroke-width="2"
                :class="['pointer-events-auto', h.cursor, 'hover:scale-125 transition-transform']"
                @pointerdown.stop="onResizeHandlePointerDown($event, h.id)"
              />
            </g>

            <!-- Locked Active Layer: Locked Indicator -->
            <g
              v-else-if="activeLayer && activeLayerBounds && activeLayer.locked"
              :transform="`translate(${activeLayerBounds.x}, ${activeLayerBounds.y}) rotate(${activeLayerBounds.rotation})`"
            >
              <rect
                :x="-activeLayerBounds.hw"
                :y="-activeLayerBounds.hh"
                :width="activeLayerBounds.hw * 2"
                :height="activeLayerBounds.hh * 2"
                fill="none"
                stroke="#F59E0B"
                stroke-width="1.5"
                stroke-dasharray="4 4"
              />
              <text x="0" y="0" fill="#F59E0B" font-size="28" text-anchor="middle" dominant-baseline="middle">
                🔒
              </text>
            </g>
          </svg>

          <!-- Floating Info Overlay -->
          <div class="absolute bottom-3 left-3 px-3 py-1.5 rounded-lg bg-black/60 backdrop-blur border border-white/10 text-[11px] text-neutral-300 font-mono pointer-events-none">
            {{ studioState.composition.title }} • {{ studioState.composition.layers.length }} Layers • 1024x1024
          </div>
        </div>
      </section>

      <!-- Right Sidebar: Layers & Inspector -->
      <aside class="w-84 border-l border-white/10 bg-black/40 flex flex-col">
        <!-- Sidebar Tabs -->
        <div class="flex items-center border-b border-white/10 p-2 gap-2 text-xs font-bold">
          <button
            @click="studioState.activeSideTab = 'layers'"
            :class="[
              'flex-1 py-2 rounded-lg transition-all',
              studioState.activeSideTab === 'layers'
                ? 'bg-white/15 text-white'
                : 'text-neutral-400 hover:text-white',
            ]"
          >
            Layers Stack
          </button>
          <button
            @click="studioState.activeSideTab = 'inspector'"
            :class="[
              'flex-1 py-2 rounded-lg transition-all',
              studioState.activeSideTab === 'inspector'
                ? 'bg-white/15 text-white'
                : 'text-neutral-400 hover:text-white',
            ]"
          >
            Layer Inspector
          </button>
          <button
            @click="studioState.activeSideTab = 'styles'"
            :class="[
              'flex-1 py-2 rounded-lg transition-all',
              studioState.activeSideTab === 'styles'
                ? 'bg-white/15 text-white'
                : 'text-neutral-400 hover:text-white',
            ]"
          >
            Brushes
          </button>
        </div>

        <!-- TAB 1: NON-DESTRUCTIVE LAYERS STACK -->
        <div v-if="studioState.activeSideTab === 'layers'" class="flex-1 overflow-y-auto p-4 space-y-3">
          <div class="flex items-center justify-between pb-2 border-b border-white/10">
            <span class="text-xs font-bold uppercase tracking-wider text-neutral-400">Layers (Top to Bottom)</span>
            <div class="flex items-center gap-1">
              <button
                @click="addFreehandLayer()"
                class="px-2 py-1 text-[10px] font-bold rounded bg-white/10 hover:bg-white/20"
                title="Add Freehand Layer"
              >
                + Paint
              </button>
              <button
                @click="addTextLayer()"
                class="px-2 py-1 text-[10px] font-bold rounded bg-white/10 hover:bg-white/20"
                title="Add Text Layer"
              >
                + Text
              </button>
            </div>
          </div>

          <!-- Reversed so top of list = top rendered layer -->
          <div
            v-for="layer in [...studioState.composition.layers].reverse()"
            :key="layer.id"
            @click="selectLayer(layer.id)"
            :class="[
              'p-3 rounded-xl border transition-all cursor-pointer flex items-center justify-between gap-3',
              studioState.activeLayerId === layer.id
                ? 'bg-white/10 border-[#D6FF62] shadow-[0_0_15px_rgba(214,255,98,0.15)]'
                : 'bg-neutral-900/60 border-white/5 hover:border-white/20',
              layer.locked ? 'opacity-80' : '',
            ]"
          >
            <div class="flex items-center gap-3 min-w-0">
              <span class="text-sm">
                {{ layer.type === 'text' ? '🔤' : layer.type === 'image' ? '🖼️' : layer.type === 'stencil' ? '⭐' : '🖌️' }}
              </span>
              <div class="truncate">
                <p class="text-xs font-bold text-white truncate flex items-center gap-1.5">
                  <span>{{ layer.name }}</span>
                  <span v-if="layer.locked" class="text-[10px] text-amber-400">🔒</span>
                </p>
                <p class="text-[10px] text-neutral-400 uppercase tracking-wider">{{ layer.type }}</p>
              </div>
            </div>

            <div class="flex items-center gap-1">
              <!-- Reorder Up/Down -->
              <button
                @click.stop="reorderLayer(layer.id, 1)"
                :disabled="layer.locked"
                class="p-1 text-neutral-400 hover:text-white text-xs disabled:opacity-30"
                title="Move Up"
              >
                ▲
              </button>
              <button
                @click.stop="reorderLayer(layer.id, -1)"
                :disabled="layer.locked"
                class="p-1 text-neutral-400 hover:text-white text-xs disabled:opacity-30"
                title="Move Down"
              >
                ▼
              </button>

              <!-- Lock / Unlock Toggle -->
              <button
                @click.stop="toggleLayerLock(layer.id)"
                :class="['p-1 text-xs transition-colors', layer.locked ? 'text-amber-400 hover:text-amber-300' : 'text-neutral-500 hover:text-white']"
                :title="layer.locked ? 'Unlock Layer' : 'Lock Layer'"
              >
                {{ layer.locked ? '🔒' : '🔓' }}
              </button>

              <!-- Visibility Eye -->
              <button
                @click.stop="toggleLayerVisibility(layer.id)"
                :class="['p-1 text-xs', layer.visible ? 'text-white' : 'text-neutral-600']"
                title="Toggle Visibility"
              >
                {{ layer.visible ? '👁️' : '🕶️' }}
              </button>

              <!-- Duplicate -->
              <button
                @click.stop="duplicateLayer(layer.id)"
                class="p-1 text-neutral-400 hover:text-white text-xs"
                title="Duplicate Layer"
              >
                📋
              </button>

              <!-- Delete -->
              <button
                @click.stop="deleteLayer(layer.id)"
                :disabled="layer.locked"
                class="p-1 text-rose-400 hover:text-rose-300 text-xs disabled:opacity-30"
                title="Delete Layer"
              >
                🗑️
              </button>
            </div>
          </div>
        </div>

        <!-- TAB 2: LAYER INSPECTOR -->
        <div v-else-if="studioState.activeSideTab === 'inspector'" class="flex-1 overflow-y-auto p-4 space-y-4 text-xs">
          <div v-if="!activeLayer" class="text-neutral-500 text-center py-10">
            Select a layer to inspect its properties.
          </div>

          <!-- Locked Banner -->
          <div
            v-if="activeLayer && activeLayer.locked"
            class="p-3 bg-amber-500/10 border border-amber-500/30 rounded-xl text-amber-300 font-bold text-xs flex items-center gap-2"
          >
            <span>🔒</span>
            <span>Layer is locked. Unlock it in the Layers Stack to make changes.</span>
          </div>

          <fieldset
            v-if="activeLayer"
            :disabled="activeLayer.locked"
            :class="['space-y-4', activeLayer.locked ? 'opacity-50 pointer-events-none' : '']"
          >
            <!-- TEXT LAYER INSPECTOR -->
            <div v-if="activeLayer.type === 'text'" class="space-y-4">
              <div>
                <label class="block text-neutral-400 font-bold mb-1">Text Content</label>
                <textarea
                  v-model="(activeLayer as TextLayer).text"
                  rows="2"
                  class="w-full bg-neutral-900 border border-white/10 rounded-lg p-2.5 text-white font-bold focus:border-[#D6FF62] outline-none"
                />
              </div>

              <div class="grid grid-cols-2 gap-3">
                <div>
                  <label class="block text-neutral-400 font-bold mb-1">Font Family</label>
                  <select
                    v-model="(activeLayer as TextLayer).font"
                    class="w-full bg-neutral-900 border border-white/10 rounded-lg p-2 text-white outline-none"
                  >
                    <option v-for="font in FONTS" :key="font" :value="font">{{ font }}</option>
                  </select>
                </div>
                <div>
                  <label class="block text-neutral-400 font-bold mb-1">Font Size</label>
                  <input
                    v-model.number="(activeLayer as TextLayer).fontSize"
                    type="number"
                    min="16"
                    max="200"
                    class="w-full bg-neutral-900 border border-white/10 rounded-lg p-2 text-white outline-none"
                  />
                </div>
              </div>

              <!-- Color Palette -->
              <div>
                <label class="block text-neutral-400 font-bold mb-1">Text Color</label>
                <div class="flex flex-wrap gap-1.5 items-center">
                  <button
                    v-for="color in COLOR_PRESETS"
                    :key="color"
                    @click="(activeLayer as TextLayer).color = color"
                    class="w-6 h-6 rounded-md border border-white/10 hover:scale-110 transition-all"
                    :style="{ backgroundColor: color }"
                  />
                  <input
                    v-model="(activeLayer as TextLayer).color"
                    type="color"
                    class="w-6 h-6 rounded cursor-pointer border-0 bg-transparent"
                  />
                </div>
              </div>

              <!-- Effects Section -->
              <div class="border-t border-white/10 pt-3 space-y-3">
                <h4 class="font-bold text-neutral-300">Graffiti Text Effects</h4>

                <!-- Drip Effect -->
                <div class="bg-neutral-900/60 p-2.5 rounded-xl border border-white/5 space-y-2">
                  <div class="flex items-center justify-between">
                    <span class="font-bold">Paint Drips</span>
                    <input type="checkbox" v-model="(activeLayer as TextLayer).drip.enabled" />
                  </div>
                  <div v-if="(activeLayer as TextLayer).drip.enabled" class="space-y-1.5">
                    <div class="flex justify-between text-[11px] text-neutral-400">
                      <span>Length: {{ (activeLayer as TextLayer).drip.length }}px</span>
                    </div>
                    <input
                      type="range"
                      min="10"
                      max="120"
                      v-model.number="(activeLayer as TextLayer).drip.length"
                      class="w-full"
                    />
                  </div>
                </div>

                <!-- Neon Glow Effect -->
                <div class="bg-neutral-900/60 p-2.5 rounded-xl border border-white/5 space-y-2">
                  <div class="flex items-center justify-between">
                    <span class="font-bold">Neon Glow</span>
                    <input type="checkbox" v-model="(activeLayer as TextLayer).glow.enabled" />
                  </div>
                  <div v-if="(activeLayer as TextLayer).glow.enabled" class="space-y-1.5">
                    <input
                      type="range"
                      min="2"
                      max="40"
                      v-model.number="(activeLayer as TextLayer).glow.blur"
                      class="w-full"
                    />
                  </div>
                </div>

                <!-- Outline Effect -->
                <div class="bg-neutral-900/60 p-2.5 rounded-xl border border-white/5 space-y-2">
                  <div class="flex items-center justify-between">
                    <span class="font-bold">Chisel Outline</span>
                    <input type="checkbox" v-model="(activeLayer as TextLayer).outline.enabled" />
                  </div>
                  <div v-if="(activeLayer as TextLayer).outline.enabled" class="space-y-1.5">
                    <input
                      type="range"
                      min="1"
                      max="16"
                      v-model.number="(activeLayer as TextLayer).outline.width"
                      class="w-full"
                    />
                  </div>
                </div>

                <!-- Distress Weathering -->
                <div class="bg-neutral-900/60 p-2.5 rounded-xl border border-white/5 space-y-2">
                  <div class="flex items-center justify-between">
                    <span class="font-bold">Weathering / Distress</span>
                    <input type="checkbox" v-model="(activeLayer as TextLayer).distress.enabled" />
                  </div>
                  <div v-if="(activeLayer as TextLayer).distress.enabled" class="space-y-1.5">
                    <input
                      type="range"
                      min="0.1"
                      max="0.8"
                      step="0.05"
                      v-model.number="(activeLayer as TextLayer).distress.roughness"
                      class="w-full"
                    />
                  </div>
                </div>
              </div>
            </div>

            <!-- IMAGE LAYER INSPECTOR -->
            <div v-else-if="activeLayer.type === 'image'" class="space-y-4">
              <h4 class="font-bold text-neutral-300">Image Adjustments</h4>
              <div class="space-y-3">
                <div>
                  <label class="block text-neutral-400 font-bold mb-1">Scale / Size</label>
                  <input
                    type="range"
                    min="80"
                    max="800"
                    v-model.number="(activeLayer as ImageLayer).width"
                    @input="(activeLayer as ImageLayer).height = (activeLayer as ImageLayer).width"
                    class="w-full"
                  />
                </div>
                <div>
                  <label class="block text-neutral-400 font-bold mb-1">Rotation ({{ (activeLayer as ImageLayer).rotation }}°)</label>
                  <input
                    type="range"
                    min="-180"
                    max="180"
                    v-model.number="(activeLayer as ImageLayer).rotation"
                    class="w-full"
                  />
                </div>
                <div class="flex items-center gap-3">
                  <button
                    @click="(activeLayer as ImageLayer).flipX = !(activeLayer as ImageLayer).flipX"
                    class="flex-1 py-1.5 bg-white/10 rounded font-bold"
                  >
                    Flip H
                  </button>
                  <button
                    @click="(activeLayer as ImageLayer).flipY = !(activeLayer as ImageLayer).flipY"
                    class="flex-1 py-1.5 bg-white/10 rounded font-bold"
                  >
                    Flip V
                  </button>
                </div>
                <div class="border-t border-white/10 pt-3 space-y-2">
                  <div class="flex items-center justify-between">
                    <span class="font-bold">Monochrome B&W</span>
                    <input type="checkbox" v-model="(activeLayer as ImageLayer).filters.monochrome" />
                  </div>
                  <div class="flex items-center justify-between">
                    <span class="font-bold">Auto Background Removal</span>
                    <input type="checkbox" v-model="(activeLayer as ImageLayer).filters.removeBg" />
                  </div>
                </div>
              </div>
            </div>

            <!-- STENCIL LAYER INSPECTOR -->
            <div v-else-if="activeLayer.type === 'stencil'" class="space-y-4">
              <h4 class="font-bold text-neutral-300">Stencil Options</h4>
              <div class="grid grid-cols-3 gap-2">
                <button
                  v-for="(_, stKey) in STENCILS"
                  :key="stKey"
                  @click="(activeLayer as StencilLayer).stencilId = stKey"
                  :class="[
                    'p-2 rounded-lg border text-center font-bold text-xs',
                    (activeLayer as StencilLayer).stencilId === stKey
                      ? 'border-[#D6FF62] bg-[#D6FF62]/20 text-[#D6FF62]'
                      : 'border-white/10 bg-white/5 text-neutral-300',
                  ]"
                >
                  {{ stKey }}
                </button>
              </div>
            </div>
          </fieldset>
        </div>

        <!-- TAB 3: TEXTURED BRUSH PRESETS -->
        <div v-else class="flex-1 overflow-y-auto p-4 space-y-4 text-xs">
          <h4 class="font-bold text-neutral-300 uppercase tracking-wider text-[11px]">Textured Brush Presets</h4>
          <div class="space-y-2">
            <button
              v-for="b in BRUSH_STYLES"
              :key="b.id"
              @click="studioState.brush.style = b.id; studioState.activeTool = 'brush'"
              :class="[
                'w-full p-3 rounded-xl border text-left transition-all flex flex-col gap-0.5',
                studioState.brush.style === b.id
                  ? 'border-[#D6FF62] bg-[#D6FF62]/15 shadow-[0_0_15px_rgba(214,255,98,0.15)]'
                  : 'border-white/10 bg-neutral-900/50 hover:bg-white/5',
              ]"
            >
              <span class="font-bold text-white text-xs">{{ b.label }}</span>
              <span class="text-[10px] text-neutral-400">{{ b.desc }}</span>
            </button>
          </div>

          <!-- Brush Size & Color -->
          <div class="border-t border-white/10 pt-3 space-y-3">
            <div>
              <div class="flex justify-between text-neutral-400 font-bold mb-1">
                <span>Brush Size</span>
                <span>{{ studioState.brush.size }}px</span>
              </div>
              <input type="range" min="3" max="60" v-model.number="studioState.brush.size" class="w-full" />
            </div>

            <div>
              <label class="block text-neutral-400 font-bold mb-1">Active Color</label>
              <div class="flex flex-wrap gap-1.5">
                <button
                  v-for="col in COLOR_PRESETS"
                  :key="col"
                  @click="studioState.brush.color = col"
                  class="w-6 h-6 rounded-md border border-white/10 hover:scale-110 transition-all"
                  :style="{ backgroundColor: col }"
                />
              </div>
            </div>
          </div>
        </div>
      </aside>
    </main>

    <!-- VIEW 3: WYSIWYG 3D WALL PREVIEW -->
    <main v-else-if="studioState.activeStep === 'preview'" class="flex-1 flex overflow-hidden">
      <!-- Preview Controls Sidebar -->
      <aside class="w-80 border-r border-white/10 bg-black/40 p-6 space-y-6 text-xs overflow-y-auto">
        <div>
          <h2 class="text-xl font-black text-white">WYSIWYG 3D PREVIEW</h2>
          <p class="text-neutral-400 text-xs mt-1">
            Simulate how your graffiti tag will look on real GTA V wall materials, perspectives, and street lighting.
          </p>
        </div>

        <!-- Wall Material Selector -->
        <div>
          <label class="block font-bold text-neutral-300 mb-2">Surface Material Texture</label>
          <div class="grid grid-cols-2 gap-2">
            <button
              v-for="mat in [
                { id: 'brick', label: 'Red Brick' },
                { id: 'concrete', label: 'Rough Concrete' },
                { id: 'metal', label: 'Corrugated Metal' },
                { id: 'wood', label: 'Weathered Wood' },
                { id: 'tile', label: 'Subway Tile' },
                { id: 'clean', label: 'Clean Plaster' },
              ]"
              :key="mat.id"
              @click="studioState.preview.material = mat.id as any"
              :class="[
                'p-2.5 rounded-xl border text-center font-bold text-xs transition-all',
                studioState.preview.material === mat.id
                  ? 'border-[#D6FF62] bg-[#D6FF62]/20 text-[#D6FF62]'
                  : 'border-white/10 bg-white/5 text-neutral-300 hover:bg-white/10',
              ]"
            >
              {{ mat.label }}
            </button>
          </div>
        </div>

        <!-- Lighting Simulator -->
        <div>
          <label class="block font-bold text-neutral-300 mb-2">Lighting & Environment</label>
          <div class="grid grid-cols-2 gap-2">
            <button
              v-for="lit in [
                { id: 'street', label: '🌙 Streetlamp' },
                { id: 'day', label: '☀️ Broad Daylight' },
                { id: 'night', label: '🌑 Dark Alley' },
                { id: 'rain', label: '🌧️ Wet / Rain' },
              ]"
              :key="lit.id"
              @click="studioState.preview.lighting = lit.id as any"
              :class="[
                'p-2 rounded-xl border text-center font-bold text-xs transition-all',
                studioState.preview.lighting === lit.id
                  ? 'border-[#D6FF62] bg-[#D6FF62]/20 text-[#D6FF62]'
                  : 'border-white/10 bg-white/5 text-neutral-300 hover:bg-white/10',
              ]"
            >
              {{ lit.label }}
            </button>
          </div>
        </div>

        <!-- 3D Perspective Tilt -->
        <div class="space-y-3">
          <label class="block font-bold text-neutral-300">Wall Perspective Angle</label>
          <div>
            <div class="flex justify-between text-neutral-400 mb-1">
              <span>Horizontal Angle: {{ studioState.preview.perspectiveY }}°</span>
            </div>
            <input type="range" min="-35" max="35" v-model.number="studioState.preview.perspectiveY" class="w-full" />
          </div>
          <div>
            <div class="flex justify-between text-neutral-400 mb-1">
              <span>Vertical Tilt: {{ studioState.preview.perspectiveX }}°</span>
            </div>
            <input type="range" min="-25" max="25" v-model.number="studioState.preview.perspectiveX" class="w-full" />
          </div>
        </div>

        <button
          @click="startPlacement"
          class="w-full py-3 rounded-xl bg-emerald-500 hover:bg-emerald-400 text-black font-black uppercase tracking-wider text-xs shadow-[0_0_25px_rgba(16,185,129,0.3)] transition-all"
        >
          Confirm & Place on Wall
        </button>
      </aside>

      <!-- 3D Wall Viewport -->
      <section class="flex-1 bg-neutral-950 flex items-center justify-center p-12 overflow-hidden perspective-[1200px]">
        <div
          class="relative w-[560px] h-[560px] rounded-2xl shadow-2xl transition-transform duration-200 overflow-hidden flex items-center justify-center"
          :style="{
            transform: `rotateX(${studioState.preview.perspectiveX}deg) rotateY(${studioState.preview.perspectiveY}deg)`,
            backgroundColor:
              studioState.preview.material === 'brick' ? '#5c221a' :
              studioState.preview.material === 'concrete' ? '#2e2e2e' :
              studioState.preview.material === 'metal' ? '#1f2937' :
              studioState.preview.material === 'wood' ? '#3e2723' : '#111827',
            backgroundImage:
              studioState.preview.material === 'brick' ? 'repeating-linear-gradient(0deg, #3d140e 0, #3d140e 4px, transparent 4px, transparent 40px), repeating-linear-gradient(90deg, #3d140e 0, #3d140e 4px, transparent 4px, transparent 80px)' :
              studioState.preview.material === 'concrete' ? 'radial-gradient(#444 1px, transparent 1px)' : 'none',
            backgroundSize: studioState.preview.material === 'concrete' ? '12px 12px' : 'auto',
          }"
        >
          <!-- Lighting overlay -->
          <div
            class="absolute inset-0 pointer-events-none"
            :style="{
              background:
                studioState.preview.lighting === 'street' ? 'radial-gradient(circle at 40% 30%, rgba(254,240,138,0.25) 0%, rgba(0,0,0,0.85) 75%)' :
                studioState.preview.lighting === 'night' ? 'rgba(0,0,0,0.65)' :
                studioState.preview.lighting === 'rain' ? 'radial-gradient(circle, rgba(255,255,255,0.15) 0%, rgba(0,0,0,0.7) 100%)' :
                'linear-gradient(to bottom, rgba(255,255,255,0.15), rgba(0,0,0,0.2))',
            }"
          />

          <!-- Preview Canvas -->
          <canvas
            ref="previewCanvasRef"
            width="1024"
            height="1024"
            class="w-full h-full object-contain relative z-10 filter drop-shadow-2xl"
          />
        </div>
      </section>
    </main>

    <!-- VIEW 4: SMART PLACEMENT CONFIGURATION -->
    <main v-else-if="studioState.activeStep === 'placement'" class="flex-1 p-8 max-w-4xl mx-auto w-full flex flex-col justify-center">
      <div class="bg-neutral-900/80 border border-white/15 rounded-3xl p-8 backdrop-blur-2xl shadow-2xl space-y-6">
        <div>
          <h2 class="text-2xl font-black text-white">SMART PLACEMENT TOOLS</h2>
          <p class="text-neutral-400 text-sm mt-1">
            Configure snapping, alignment guides, and sizing presets before raycasting the spray onto the wall.
          </p>
        </div>

        <!-- Sizing Presets -->
        <div>
          <label class="block font-bold text-neutral-300 text-xs mb-2 uppercase tracking-wider">Sizing Presets</label>
          <div class="grid grid-cols-2 md:grid-cols-5 gap-3">
            <button
              v-for="sz in [
                { id: 'small', label: 'Small Tag', size: '0.8m' },
                { id: 'medium', label: 'Standard', size: '1.6m' },
                { id: 'large', label: 'Large Tag', size: '2.5m' },
                { id: 'mural', label: 'Street Mural', size: '4.0m' },
                { id: 'fit', label: 'Fit to Wall', size: 'Auto-Fit' },
              ]"
              :key="sz.id"
              @click="studioState.placement.presetSize = sz.id as any"
              :class="[
                'p-3.5 rounded-2xl border text-left transition-all',
                studioState.placement.presetSize === sz.id
                  ? 'border-[#D6FF62] bg-[#D6FF62]/15 text-[#D6FF62] shadow-[0_0_20px_rgba(214,255,98,0.2)]'
                  : 'border-white/10 bg-white/5 text-neutral-300 hover:bg-white/10',
              ]"
            >
              <p class="font-bold text-xs">{{ sz.label }}</p>
              <p class="text-[10px] text-neutral-400 mt-0.5">{{ sz.size }}</p>
            </button>
          </div>
        </div>

        <!-- Snapping Toggles -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 border-t border-white/10 pt-6">
          <div class="bg-black/40 p-4 rounded-2xl border border-white/10 flex items-center justify-between">
            <div>
              <p class="font-bold text-sm text-white">Surface Snapping</p>
              <p class="text-xs text-neutral-400">Magnetically align to wall normal</p>
            </div>
            <input type="checkbox" v-model="studioState.placement.snapSurface" class="w-5 h-5 accent-[#D6FF62]" />
          </div>

          <div class="bg-black/40 p-4 rounded-2xl border border-white/10 flex items-center justify-between">
            <div>
              <p class="font-bold text-sm text-white">Rotation Snapping</p>
              <p class="text-xs text-neutral-400">Snap to 0°, 45°, 90°, 180°</p>
            </div>
            <input type="checkbox" v-model="studioState.placement.snapRotation" class="w-5 h-5 accent-[#D6FF62]" />
          </div>

          <div class="bg-black/40 p-4 rounded-2xl border border-white/10 flex items-center justify-between">
            <div>
              <p class="font-bold text-sm text-white">Duplicate Placement</p>
              <p class="text-xs text-neutral-400">Keep placing without re-opening</p>
            </div>
            <input type="checkbox" v-model="studioState.placement.duplicateMode" class="w-5 h-5 accent-[#D6FF62]" />
          </div>
        </div>

        <div class="pt-4 flex items-center justify-end gap-3">
          <button
            @click="studioState.activeStep = 'studio'"
            class="px-6 py-3 rounded-xl bg-neutral-800 text-neutral-300 font-bold text-xs hover:bg-neutral-700 transition-all"
          >
            Back to Editor
          </button>
          <button
            @click="startPlacement"
            class="px-8 py-3 rounded-xl bg-[#D6FF62] text-black font-black uppercase tracking-wider text-xs shadow-[0_0_25px_rgba(214,255,98,0.3)] hover:scale-105 transition-all"
          >
            Start Wall Placement Raycast →
          </button>
        </div>
      </div>
    </main>

    <!-- ─── MODAL 1: ADVANCED IMAGE IMPORTER ────────────────────────────── -->
    <div
      v-if="studioState.imageModal.visible"
      class="fixed inset-0 z-[300] bg-black/80 backdrop-blur-md flex items-center justify-center p-6"
    >
      <div class="bg-neutral-900 border border-white/20 rounded-3xl p-6 max-w-xl w-full space-y-5 shadow-2xl">
        <div class="flex items-center justify-between border-b border-white/10 pb-3">
          <h3 class="font-black text-lg text-white">ADVANCED IMAGE IMPORTER</h3>
          <button @click="studioState.imageModal.visible = false" class="text-neutral-400 hover:text-white">✕</button>
        </div>

        <!-- Direct URL or Paste Zone -->
        <div class="space-y-3">
          <div>
            <label class="block text-xs font-bold text-neutral-400 mb-1">Image URL (Imgur, Discord, etc.)</label>
            <input
              v-model="studioState.imageModal.url"
              type="text"
              placeholder="https://i.imgur.com/..."
              class="w-full bg-black/60 border border-white/10 rounded-xl p-3 text-xs text-white outline-none focus:border-[#D6FF62]"
            />
          </div>

          <div class="p-4 border-2 border-dashed border-white/15 rounded-2xl text-center bg-black/30">
            <p class="text-xs text-neutral-300 font-bold">📋 Paste directly from Clipboard (Ctrl+V)</p>
            <p class="text-[11px] text-neutral-500 mt-1">Or drag & drop any image file onto the screen</p>
          </div>
        </div>

        <!-- Filters & BG Removal -->
        <div class="border-t border-white/10 pt-4 space-y-3 text-xs">
          <h4 class="font-bold text-neutral-300">Filters & Background Cleanup</h4>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <div class="flex justify-between text-neutral-400 mb-1">
                <span>Brightness ({{ studioState.imageModal.brightness }}%)</span>
              </div>
              <input type="range" min="-60" max="60" v-model.number="studioState.imageModal.brightness" class="w-full" />
            </div>
            <div>
              <div class="flex justify-between text-neutral-400 mb-1">
                <span>Contrast ({{ studioState.imageModal.contrast }}%)</span>
              </div>
              <input type="range" min="-60" max="60" v-model.number="studioState.imageModal.contrast" class="w-full" />
            </div>
          </div>

          <div class="flex items-center justify-between p-3 rounded-xl bg-black/40 border border-white/5">
            <div>
              <p class="font-bold text-white">Remove Background</p>
              <p class="text-[11px] text-neutral-400">Make solid outer color transparent</p>
            </div>
            <input type="checkbox" v-model="studioState.imageModal.removeBg" class="w-4 h-4 accent-[#D6FF62]" />
          </div>

          <div v-if="studioState.imageModal.removeBg" class="pl-2">
            <div class="flex justify-between text-neutral-400 mb-1">
              <span>Removal Tolerance: {{ studioState.imageModal.removeBgThreshold }}%</span>
            </div>
            <input type="range" min="5" max="80" v-model.number="studioState.imageModal.removeBgThreshold" class="w-full" />
          </div>

          <div class="flex items-center justify-between p-3 rounded-xl bg-black/40 border border-white/5">
            <div>
              <p class="font-bold text-white">Monochrome / Black & White</p>
              <p class="text-[11px] text-neutral-400">Convert to street stencil style</p>
            </div>
            <input type="checkbox" v-model="studioState.imageModal.monochrome" class="w-4 h-4 accent-[#D6FF62]" />
          </div>
        </div>

        <div class="flex items-center justify-end gap-3 pt-2">
          <button
            @click="studioState.imageModal.visible = false"
            class="px-4 py-2 rounded-lg bg-white/10 text-neutral-300 text-xs font-bold"
          >
            Cancel
          </button>
          <button
            @click="confirmImageImport"
            class="px-5 py-2 rounded-lg bg-[#D6FF62] text-black font-black text-xs uppercase tracking-wider"
          >
            Add Image to Layer
          </button>
        </div>
      </div>
    </div>

    <!-- ─── MODAL 2: GANG OFFICIAL TEMPLATE ─────────────────────────────── -->
    <div
      v-if="studioState.gangModal.visible"
      class="fixed inset-0 z-[300] bg-black/80 backdrop-blur-md flex items-center justify-center p-6"
    >
      <div class="bg-neutral-900 border border-amber-500/30 rounded-3xl p-6 max-w-md w-full space-y-4 shadow-2xl">
        <div class="flex items-center justify-between border-b border-white/10 pb-3">
          <h3 class="font-black text-lg text-amber-400">👑 PUBLISH GANG TAG</h3>
          <button @click="studioState.gangModal.visible = false" class="text-neutral-400 hover:text-white">✕</button>
        </div>

        <p class="text-xs text-neutral-300">
          Designate this spray as an authorized tag for all crew members. They can access and spray this from their Gang Library!
        </p>

        <div>
          <label class="block text-xs font-bold text-neutral-400 mb-1">Official Tag Title</label>
          <input
            v-model="studioState.gangModal.title"
            type="text"
            placeholder="Official Turf Tag"
            class="w-full bg-black/60 border border-white/10 rounded-xl p-3 text-xs text-white outline-none focus:border-amber-400"
          />
        </div>

        <div>
          <label class="block text-xs font-bold text-neutral-400 mb-1">Variant Type</label>
          <select
            v-model="studioState.gangModal.variant"
            class="w-full bg-black/60 border border-white/10 rounded-xl p-3 text-xs text-white outline-none"
          >
            <option value="official">Official Crew Tag</option>
            <option value="small">Small Street Tag</option>
            <option value="mural">Large Mural</option>
            <option value="territory_mark">Territory Mark</option>
            <option value="monochrome">Monochrome / Low-Profile</option>
          </select>
        </div>

        <div class="flex items-center justify-end gap-3 pt-2">
          <button
            @click="studioState.gangModal.visible = false"
            class="px-4 py-2 rounded-lg bg-white/10 text-neutral-300 text-xs font-bold"
          >
            Cancel
          </button>
          <button
            @click="publishGangOfficial"
            class="px-5 py-2 rounded-lg bg-amber-400 hover:bg-amber-300 text-black font-black text-xs uppercase tracking-wider"
          >
            Publish to Crew
          </button>
        </div>
      </div>
    </div>

    <!-- ─── MODAL 3: JSON IMPORT / EXPORT ──────────────────────────────── -->
    <div
      v-if="studioState.jsonModal.visible"
      class="fixed inset-0 z-[300] bg-black/80 backdrop-blur-md flex items-center justify-center p-6"
    >
      <div class="bg-neutral-900 border border-white/20 rounded-3xl p-6 max-w-xl w-full space-y-4 shadow-2xl">
        <div class="flex items-center justify-between border-b border-white/10 pb-3">
          <h3 class="font-black text-lg text-white">
            {{ studioState.jsonModal.mode === 'export' ? 'EXPORT DESIGN JSON' : 'IMPORT DESIGN JSON' }}
          </h3>
          <button @click="studioState.jsonModal.visible = false" class="text-neutral-400 hover:text-white">✕</button>
        </div>

        <textarea
          v-model="studioState.jsonModal.content"
          rows="10"
          class="w-full bg-black/70 border border-white/10 rounded-xl p-3 text-xs text-emerald-400 font-mono outline-none focus:border-[#D6FF62]"
          :placeholder="studioState.jsonModal.mode === 'import' ? 'Paste Peak Spray composition JSON here...' : ''"
        />

        <p v-if="studioState.jsonModal.error" class="text-xs text-rose-400 font-bold">
          {{ studioState.jsonModal.error }}
        </p>

        <div class="flex items-center justify-between pt-2">
          <span v-if="studioState.jsonModal.copied" class="text-xs text-[#D6FF62] font-bold">
            ✓ Copied to clipboard!
          </span>
          <span v-else></span>

          <div class="flex items-center gap-3">
            <button
              @click="studioState.jsonModal.visible = false"
              class="px-4 py-2 rounded-lg bg-white/10 text-neutral-300 text-xs font-bold"
            >
              Cancel
            </button>
            <button
              v-if="studioState.jsonModal.mode === 'export'"
              @click="copyJsonToClipboard"
              class="px-5 py-2 rounded-lg bg-[#D6FF62] text-black font-black text-xs uppercase"
            >
              Copy JSON
            </button>
            <button
              v-else
              @click="executeImportJson"
              class="px-5 py-2 rounded-lg bg-[#D6FF62] text-black font-black text-xs uppercase"
            >
              Import Design
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Glass-morphic scrollbar */
::-webkit-scrollbar {
  width: 6px;
  height: 6px;
}
::-webkit-scrollbar-track {
  background: rgba(0, 0, 0, 0.2);
}
::-webkit-scrollbar-thumb {
  background: rgba(255, 255, 255, 0.15);
  border-radius: 9999px;
}
::-webkit-scrollbar-thumb:hover {
  background: rgba(214, 255, 98, 0.5);
}
</style>
