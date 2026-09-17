import { reactive, ref } from 'vue'
import type {
  BrushStyleId,
  DesignLibrary,
  DesignRecord,
  FreehandLayer,
  FreehandStroke,
  GraffitiComposition,
  GraffitiLayer,
  ImageFilters,
  ImageLayer,
  StencilLayer,
  TextLayer,
} from '@/types/graffiti'

export const showStudio = ref(false)

export function createDefaultComposition(title = 'New Tag'): GraffitiComposition {
  return {
    version: '1.0.0',
    title,
    width: 1024,
    height: 1024,
    background: 'transparent',
    layers: [
      {
        id: 'layer_' + Math.random().toString(36).substring(2, 9),
        name: 'Freehand Tag',
        type: 'freehand',
        visible: true,
        locked: false,
        opacity: 1.0,
        brushStyle: 'spray',
        strokes: [],
      } as FreehandLayer,
    ],
  }
}

export interface StudioTransaction {
  description: string
  apply: () => boolean
  undo: () => void
  estimatedBytes?: number
}

const MAX_TRANSACTIONS = 50
const MAX_HISTORY_BYTES = 20 * 1024 * 1024 // 20 MB memory budget

export const studioState = reactive({
  activeStep: 'studio' as 'library' | 'studio' | 'preview' | 'placement',
  activeTool: 'brush' as 'select' | 'brush' | 'text' | 'image' | 'stencil',
  activeSideTab: 'layers' as 'layers' | 'inspector' | 'styles',

  composition: createDefaultComposition(),
  activeLayerId: null as string | null,

  // Persistence and Ownership Separation
  activeRecordId: null as number | null,
  activeRecordMetadata: null as {
    id: number | null
    identifier?: string
    category: 'draft' | 'saved' | 'template' | 'gang'
    variant: string
    isOwner: boolean
    isServerTemplate: boolean
    forkedFromId?: number
    forkedFromTitle?: string
  } | null,
  playerIdentifier: '' as string,
  isDirty: false,

  brush: {
    style: 'spray' as BrushStyleId,
    size: 14,
    color: '#D6FF62',
    density: 0.7,
    pressure: 0.85,
    scatter: 1.0,
  },

  preview: {
    material: 'brick' as 'concrete' | 'brick' | 'metal' | 'wood' | 'tile' | 'clean',
    perspectiveX: 0,
    perspectiveY: 0,
    lighting: 'street' as 'day' | 'night' | 'street' | 'rain',
    zoom: 1.0,
  },

  library: {
    drafts: [],
    saved: [],
    recent: [],
    templates: [],
    gang: [],
    playerGang: undefined,
    playerIdentifier: '',
  } as DesignLibrary,

  activeLibraryTab: 'saved' as 'saved' | 'drafts' | 'templates' | 'gang' | 'recent',

  imageModal: {
    visible: false,
    url: '',
    dataUrl: '',
    brightness: 0,
    contrast: 0,
    monochrome: false,
    blur: 0,
    removeBg: false,
    removeBgThreshold: 25,
  },

  gangModal: {
    visible: false,
    title: '',
    variant: 'default',
  },

  jsonModal: {
    visible: false,
    mode: 'export' as 'export' | 'import',
    content: '',
    copied: false,
    error: '',
  },

  placement: {
    presetSize: 'medium' as 'small' | 'medium' | 'large' | 'mural' | 'fit',
    snapSurface: true,
    snapRotation: true,
    rotationDeg: 0,
    duplicateMode: false,
  },

  undoStack: [] as StudioTransaction[],
  redoStack: [] as StudioTransaction[],
  historyBytes: 0,
  batchSnapshot: null as { layerId: string; description: string; beforeData: any } | null,
})

// ─── Transactional Undo / Redo Mechanism ─────────────────────────────

export function executeTransaction(transaction: StudioTransaction): boolean {
  const success = transaction.apply()
  if (success === false) return false

  studioState.undoStack.push(transaction)
  studioState.redoStack = [] // Clear redo on new action
  studioState.isDirty = true

  const bytes = transaction.estimatedBytes || 256
  studioState.historyBytes += bytes

  // Bound by count
  if (studioState.undoStack.length > MAX_TRANSACTIONS) {
    const dropped = studioState.undoStack.shift()
    studioState.historyBytes -= dropped?.estimatedBytes || 256
  }

  // Bound by memory
  while (studioState.historyBytes > MAX_HISTORY_BYTES && studioState.undoStack.length > 1) {
    const dropped = studioState.undoStack.shift()
    studioState.historyBytes -= dropped?.estimatedBytes || 256
  }

  return true
}

export function undoStudio(): boolean {
  if (studioState.undoStack.length === 0) return false
  const action = studioState.undoStack.pop()!
  action.undo()
  studioState.redoStack.push(action)
  return true
}

export function redoStudio(): boolean {
  if (studioState.redoStack.length === 0) return false
  const action = studioState.redoStack.pop()!
  action.apply()
  studioState.undoStack.push(action)
  return true
}

export function resetStudioHistory() {
  studioState.undoStack = []
  studioState.redoStack = []
  studioState.historyBytes = 0
  studioState.batchSnapshot = null
}

// ─── Document Loading & Normalization Boundary ───────────────────────

export function normalizeCompositionData(raw: any): GraffitiComposition {
  if (!raw || typeof raw !== 'object') {
    throw new Error('Composition payload is missing or not an object')
  }

  const width = typeof raw.width === 'number' && raw.width >= 256 && raw.width <= 2048 ? raw.width : 1024
  const height = typeof raw.height === 'number' && raw.height >= 256 && raw.height <= 2048 ? raw.height : 1024
  const title = typeof raw.title === 'string' && raw.title.trim() ? raw.title.trim() : 'Untitled Tag'
  const background = typeof raw.background === 'string' ? raw.background : 'transparent'
  const layers = Array.isArray(raw.layers) ? JSON.parse(JSON.stringify(raw.layers)) : []

  return {
    version: raw.version || '1.0.0',
    title,
    width,
    height,
    background,
    layers,
    eraseMask: Array.isArray(raw.eraseMask) ? raw.eraseMask : [],
  }
}

/**
 * Validates and normalizes an incoming record before replacing current work.
 * Handles owned update preservation vs fork-on-open.
 */
export function openDesign(
  record: DesignRecord | any,
  options: { allowTemplateEdit?: boolean } = {}
): { success: boolean; message?: string } {
  if (!record || typeof record !== 'object') {
    return { success: false, message: 'Invalid design record structure' }
  }

  // Extract nested composition or root layers
  const compSource = record.composition || (record.layers ? record : null)
  if (!compSource) {
    return { success: false, message: 'Design record does not contain artwork composition' }
  }

  let normalized: GraffitiComposition
  try {
    normalized = normalizeCompositionData(compSource)
  } catch (err: any) {
    // Current open document remains 100% intact!
    return { success: false, message: `Corrupted artwork data: ${err.message}` }
  }

  // Determine ownership & forking
  const isServerTemplate = record.isServerTemplate === true || record.category === 'template'
  const currentPid = studioState.playerIdentifier || studioState.library.playerIdentifier || ''
  const isOwner = Boolean(currentPid && record.identifier && record.identifier === currentPid && !isServerTemplate)
  const canEditTemplate = options.allowTemplateEdit && isServerTemplate

  if (isOwner || canEditTemplate) {
    // Preserve update identity
    studioState.activeRecordId = typeof record.id === 'number' ? record.id : null
    studioState.activeRecordMetadata = {
      id: studioState.activeRecordId,
      identifier: record.identifier,
      category: record.category || 'saved',
      variant: record.variant || 'default',
      isOwner: true,
      isServerTemplate,
    }
  } else {
    // Fork to new personal design!
    studioState.activeRecordId = null
    studioState.activeRecordMetadata = {
      id: null,
      identifier: currentPid,
      category: 'saved',
      variant: 'default',
      isOwner: false,
      isServerTemplate: false,
      forkedFromId: record.id,
      forkedFromTitle: record.title,
    }
  }

  studioState.composition = normalized
  studioState.activeLayerId = normalized.layers.length > 0 ? normalized.layers[0].id : null
  studioState.isDirty = false
  resetStudioHistory()

  return { success: true }
}

export function newComposition(title = 'New Graffiti Tag') {
  studioState.composition = createDefaultComposition(title)
  studioState.activeRecordId = null
  studioState.activeRecordMetadata = null
  studioState.activeLayerId = studioState.composition.layers[0]?.id || null
  studioState.isDirty = false
  resetStudioHistory()
}

// ─── Layer Selection & Queries ────────────────────────────────────────

export function getActiveLayer(): GraffitiLayer | null {
  if (!studioState.activeLayerId) {
    return studioState.composition.layers[studioState.composition.layers.length - 1] || null
  }
  return studioState.composition.layers.find((l) => l.id === studioState.activeLayerId) || null
}

export function selectLayer(id: string) {
  studioState.activeLayerId = id
  const layer = getActiveLayer()
  if (layer) {
    if (layer.type === 'text') studioState.activeTool = 'text'
    else if (layer.type === 'freehand') studioState.activeTool = 'brush'
    else if (layer.type === 'image') studioState.activeTool = 'image'
    else if (layer.type === 'stencil') studioState.activeTool = 'stencil'
  }
}

// ─── Layer Actions (Enforcing Lock Policy & Transactions) ──────────────

export function addLayer(layer: GraffitiLayer): boolean {
  return executeTransaction({
    description: `Add layer ${layer.name}`,
    estimatedBytes: 512,
    apply: () => {
      studioState.composition.layers.push(layer)
      studioState.activeLayerId = layer.id
      return true
    },
    undo: () => {
      const idx = studioState.composition.layers.findIndex((l) => l.id === layer.id)
      if (idx !== -1) {
        studioState.composition.layers.splice(idx, 1)
        studioState.activeLayerId = studioState.composition.layers[studioState.composition.layers.length - 1]?.id || null
      }
    },
  })
}

export function deleteLayer(id: string): boolean {
  const index = studioState.composition.layers.findIndex((l) => l.id === id)
  if (index === -1) return false
  const layer = studioState.composition.layers[index]
  if (layer.locked) return false // Locked layers resist deletion!

  return executeTransaction({
    description: `Delete layer ${layer.name}`,
    estimatedBytes: 512,
    apply: () => {
      studioState.composition.layers.splice(index, 1)
      studioState.activeLayerId = studioState.composition.layers[Math.max(0, index - 1)]?.id || null
      return true
    },
    undo: () => {
      studioState.composition.layers.splice(index, 0, layer)
      studioState.activeLayerId = layer.id
    },
  })
}

export function reorderLayer(id: string, delta: number): boolean {
  const index = studioState.composition.layers.findIndex((l) => l.id === id)
  if (index === -1) return false
  const layer = studioState.composition.layers[index]
  if (layer.locked) return false // Locked layers resist reorder

  const targetIndex = index + delta
  if (targetIndex < 0 || targetIndex >= studioState.composition.layers.length) return false

  return executeTransaction({
    description: `Reorder layer ${layer.name}`,
    estimatedBytes: 64,
    apply: () => {
      const [removed] = studioState.composition.layers.splice(index, 1)
      studioState.composition.layers.splice(targetIndex, 0, removed)
      return true
    },
    undo: () => {
      const [removed] = studioState.composition.layers.splice(targetIndex, 1)
      studioState.composition.layers.splice(index, 0, removed)
    },
  })
}

export function toggleLayerLock(id: string): boolean {
  const layer = studioState.composition.layers.find((l) => l.id === id)
  if (!layer) return false

  return executeTransaction({
    description: `Toggle lock for ${layer.name}`,
    estimatedBytes: 32,
    apply: () => {
      layer.locked = !layer.locked
      return true
    },
    undo: () => {
      layer.locked = !layer.locked
    },
  })
}

export function toggleLayerVisibility(id: string): boolean {
  const layer = studioState.composition.layers.find((l) => l.id === id)
  if (!layer) return false

  return executeTransaction({
    description: `Toggle visibility for ${layer.name}`,
    estimatedBytes: 32,
    apply: () => {
      layer.visible = !layer.visible
      return true
    },
    undo: () => {
      layer.visible = !layer.visible
    },
  })
}

export function duplicateLayer(id: string): boolean {
  const layer = studioState.composition.layers.find((l) => l.id === id)
  if (!layer) return false

  const copy: GraffitiLayer = JSON.parse(JSON.stringify(layer))
  copy.id = layer.type + '_' + Math.random().toString(36).substring(2, 9)
  copy.name = `${layer.name} (Copy)`
  copy.locked = false // Duplicates start unlocked
  if ('x' in copy) (copy as any).x += 20
  if ('y' in copy) (copy as any).y += 20

  const index = studioState.composition.layers.findIndex((l) => l.id === id)

  return executeTransaction({
    description: `Duplicate layer ${layer.name}`,
    estimatedBytes: 1024,
    apply: () => {
      studioState.composition.layers.splice(index + 1, 0, copy)
      studioState.activeLayerId = copy.id
      return true
    },
    undo: () => {
      const idx = studioState.composition.layers.findIndex((l) => l.id === copy.id)
      if (idx !== -1) {
        studioState.composition.layers.splice(idx, 1)
        studioState.activeLayerId = layer.id
      }
    },
  })
}

export function updateLayerProperty(id: string, key: string, value: any): boolean {
  const layer = studioState.composition.layers.find((l) => l.id === id)
  if (!layer || layer.locked) return false

  const beforeVal = JSON.parse(JSON.stringify((layer as any)[key]))
  const afterVal = JSON.parse(JSON.stringify(value))

  return executeTransaction({
    description: `Change ${key} on ${layer.name}`,
    estimatedBytes: 128,
    apply: () => {
      if (layer.locked) return false
      ;(layer as any)[key] = afterVal
      return true
    },
    undo: () => {
      ;(layer as any)[key] = beforeVal
    },
  })
}

export function addFreehandStroke(layerId: string, stroke: FreehandStroke): boolean {
  const layer = studioState.composition.layers.find((l) => l.id === layerId)
  if (!layer || layer.type !== 'freehand' || layer.locked) return false
  const fh = layer as FreehandLayer

  return executeTransaction({
    description: 'Draw brush stroke',
    estimatedBytes: (stroke.points?.length || 1) * 32,
    apply: () => {
      if (layer.locked) return false
      fh.strokes.push(stroke)
      return true
    },
    undo: () => {
      fh.strokes.pop()
    },
  })
}

// ─── Add Layer Conveniences ───────────────────────────────────────────

export function addTextLayer(initialText = 'PEAK') {
  const newId = 'text_' + Math.random().toString(36).substring(2, 9)
  const layer: TextLayer = {
    id: newId,
    name: `Text: ${initialText}`,
    type: 'text',
    visible: true,
    locked: false,
    opacity: 1.0,
    text: initialText,
    font: 'Rock Salt',
    fontSize: 72,
    fontWeight: 'bold',
    fontStyle: 'normal',
    letterSpacing: 3,
    lineHeight: 1.1,
    color: '#D6FF62',
    x: 512,
    y: 512,
    rotation: 0,
    scale: 1.0,
    outline: { enabled: true, color: '#000000', width: 6 },
    shadow: { enabled: true, color: '#000000', blur: 10, offsetX: 4, offsetY: 4 },
    glow: { enabled: true, color: '#D6FF62', blur: 16 },
    drip: { enabled: true, count: 4, length: 55, width: 4 },
    spray: { enabled: true, count: 12, spread: 20 },
    distress: { enabled: false, roughness: 0 },
  }
  addLayer(layer)
  studioState.activeTool = 'text'
}

export function addFreehandLayer(name = 'Freehand Spray', brushStyle: BrushStyleId = 'spray') {
  const newId = 'freehand_' + Math.random().toString(36).substring(2, 9)
  const layer: FreehandLayer = {
    id: newId,
    name,
    type: 'freehand',
    visible: true,
    locked: false,
    opacity: 1.0,
    brushStyle,
    strokes: [],
  }
  addLayer(layer)
  studioState.activeTool = 'brush'
}

export function addImageLayer(url: string, dataUrl?: string, filters?: Partial<ImageFilters>) {
  const newId = 'img_' + Math.random().toString(36).substring(2, 9)
  const layer: ImageLayer = {
    id: newId,
    name: 'Imported Image',
    type: 'image',
    visible: true,
    locked: false,
    opacity: 1.0,
    url,
    dataUrl,
    x: 512,
    y: 512,
    width: 320,
    height: 320,
    rotation: 0,
    flipX: false,
    flipY: false,
    filters: {
      brightness: filters?.brightness || 0,
      contrast: filters?.contrast || 0,
      monochrome: filters?.monochrome || false,
      blur: filters?.blur || 0,
      removeBg: filters?.removeBg || false,
      removeBgThreshold: filters?.removeBgThreshold || 25,
    },
  }
  addLayer(layer)
  studioState.activeTool = 'select'
}

export function addStencilLayer(stencilId: string) {
  const newId = 'stencil_' + Math.random().toString(36).substring(2, 9)
  const layer: StencilLayer = {
    id: newId,
    name: `Stencil (${stencilId})`,
    type: 'stencil',
    visible: true,
    locked: false,
    opacity: 1.0,
    stencilId,
    x: 512,
    y: 512,
    size: 70,
    rotation: 0,
    color: studioState.brush.color || '#D6FF62',
  }
  addLayer(layer)
  studioState.activeTool = 'stencil'
}
