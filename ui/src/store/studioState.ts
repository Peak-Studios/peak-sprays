import { reactive, ref } from 'vue'
import type {
  BrushStyleId,
  DesignLibrary,
  FreehandLayer,
  GraffitiComposition,
  GraffitiLayer,
  ImageFilters,
  ImageLayer,
  StencilLayer,
  TextLayer,
} from '@/types/graffiti'

export const showStudio = ref(false)

function createDefaultComposition(): GraffitiComposition {
  return {
    version: '1.0.0',
    title: 'New Tag',
    width: 1024,
    height: 1024,
    background: 'transparent',
    category: 'saved',
    variant: 'default',
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

export const studioState = reactive({
  activeStep: 'studio' as 'library' | 'studio' | 'preview' | 'placement',
  activeTool: 'brush' as 'select' | 'brush' | 'text' | 'image' | 'stencil',
  activeSideTab: 'layers' as 'layers' | 'inspector' | 'styles',

  composition: createDefaultComposition(),
  activeLayerId: null as string | null,

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

  history: [] as string[],
  redoStack: [] as string[],
})

// ─── Composition & Layer Actions ───────────────────────────────────────

export function pushStudioHistory() {
  const jsonStr = JSON.stringify(studioState.composition)
  studioState.history.push(jsonStr)
  if (studioState.history.length > 30) studioState.history.shift()
  studioState.redoStack = []
}

export function undoStudio() {
  if (studioState.history.length <= 1) return
  const current = studioState.history.pop()
  if (current) studioState.redoStack.push(current)
  const prev = studioState.history[studioState.history.length - 1]
  if (prev) {
    studioState.composition = JSON.parse(prev)
    if (studioState.composition.layers.length > 0) {
      studioState.activeLayerId = studioState.composition.layers[0].id
    }
  }
}

export function redoStudio() {
  if (studioState.redoStack.length === 0) return
  const next = studioState.redoStack.pop()
  if (next) {
    studioState.history.push(next)
    studioState.composition = JSON.parse(next)
    if (studioState.composition.layers.length > 0) {
      studioState.activeLayerId = studioState.composition.layers[0].id
    }
  }
}

export function loadComposition(comp: GraffitiComposition) {
  studioState.composition = JSON.parse(JSON.stringify(comp))
  if (studioState.composition.layers.length > 0) {
    studioState.activeLayerId = studioState.composition.layers[0].id
  }
  studioState.history = [JSON.stringify(studioState.composition)]
  studioState.redoStack = []
}

export function newComposition(title = 'New Graffiti Tag') {
  const comp = createDefaultComposition()
  comp.title = title
  loadComposition(comp)
}

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

export function addTextLayer(initialText = 'PEAK') {
  pushStudioHistory()
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
  studioState.composition.layers.push(layer)
  studioState.activeLayerId = newId
  studioState.activeTool = 'text'
}

export function addFreehandLayer(name = 'Freehand Spray', brushStyle: BrushStyleId = 'spray') {
  pushStudioHistory()
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
  studioState.composition.layers.push(layer)
  studioState.activeLayerId = newId
  studioState.activeTool = 'brush'
}

export function addImageLayer(url: string, dataUrl?: string, filters?: Partial<ImageFilters>) {
  pushStudioHistory()
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
  studioState.composition.layers.push(layer)
  studioState.activeLayerId = newId
  studioState.activeTool = 'select'
}

export function addStencilLayer(stencilId: string) {
  pushStudioHistory()
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
  studioState.composition.layers.push(layer)
  studioState.activeLayerId = newId
  studioState.activeTool = 'stencil'
}

export function reorderLayer(id: string, delta: number) {
  const index = studioState.composition.layers.findIndex((l) => l.id === id)
  if (index === -1) return
  const targetIndex = index + delta
  if (targetIndex < 0 || targetIndex >= studioState.composition.layers.length) return
  pushStudioHistory()
  const [removed] = studioState.composition.layers.splice(index, 1)
  studioState.composition.layers.splice(targetIndex, 0, removed)
}

export function toggleLayerVisibility(id: string) {
  const layer = studioState.composition.layers.find((l) => l.id === id)
  if (layer) {
    layer.visible = !layer.visible
  }
}

export function toggleLayerLock(id: string) {
  const layer = studioState.composition.layers.find((l) => l.id === id)
  if (layer) {
    layer.locked = !layer.locked
  }
}

export function duplicateLayer(id: string) {
  const layer = studioState.composition.layers.find((l) => l.id === id)
  if (!layer) return
  pushStudioHistory()
  const copy: GraffitiLayer = JSON.parse(JSON.stringify(layer))
  copy.id = layer.type + '_' + Math.random().toString(36).substring(2, 9)
  copy.name = `${layer.name} (Copy)`
  if ('x' in copy) (copy as any).x += 20
  if ('y' in copy) (copy as any).y += 20
  const index = studioState.composition.layers.findIndex((l) => l.id === id)
  studioState.composition.layers.splice(index + 1, 0, copy)
  studioState.activeLayerId = copy.id
}

export function deleteLayer(id: string) {
  const index = studioState.composition.layers.findIndex((l) => l.id === id)
  if (index === -1) return
  pushStudioHistory()
  studioState.composition.layers.splice(index, 1)
  if (studioState.composition.layers.length > 0) {
    studioState.activeLayerId = studioState.composition.layers[Math.max(0, index - 1)].id
  } else {
    studioState.activeLayerId = null
  }
}
