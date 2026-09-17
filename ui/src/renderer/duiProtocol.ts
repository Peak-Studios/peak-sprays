import type {
  FreehandLayer,
  FreehandStroke,
  GraffitiComposition,
  GraffitiLayer,
  ImageLayer,
  StencilLayer,
  StrokePoint,
  WorldEraseStroke,
} from '../types/graffiti.ts'
import { normalizeIncomingDocument } from './documentAdapter.ts'
import { normalizeColor } from './brushes.ts'

export type DuiActionType =
  | 'init'
  | 'loadPaintingDocument'
  | 'loadStrokes'
  | 'startStroke'
  | 'addPoint'
  | 'endStroke'
  | 'drawStroke'
  | 'stampStencil'
  | 'addImage'
  | 'updateImage'
  | 'commitImage'
  | 'cancelImage'
  | 'undo'
  | 'redo'
  | 'clear'

export interface DuiMessage {
  action: DuiActionType | string
  [key: string]: any
}

export interface DuiReducerState {
  isReady: boolean
  width: number
  height: number
  composition: GraffitiComposition
  activeStroke: FreehandStroke | null
  activeStrokeLayerId: string | null
  previewImage: ImageLayer | null
  preImageSnapshot: GraffitiComposition | null
  undoStack: GraffitiComposition[]
  redoStack: GraffitiComposition[]
  messageQueue: DuiMessage[]
  revision: number
}

function cloneComposition(comp: GraffitiComposition): GraffitiComposition {
  return JSON.parse(JSON.stringify(comp))
}

/**
 * Creates a fresh initial state for the DUI state reducer.
 */
export function createDuiReducerState(width = 1024, height = 1024): DuiReducerState {
  return {
    isReady: false,
    width,
    height,
    composition: {
      version: '1.0.0',
      title: 'DUI Canvas',
      width,
      height,
      background: 'transparent',
      layers: [],
      eraseMask: [],
    },
    activeStroke: null,
    activeStrokeLayerId: null,
    previewImage: null,
    preImageSnapshot: null,
    undoStack: [],
    redoStack: [],
    messageQueue: [],
    revision: 1,
  }
}

/**
 * Ensures an active freehand layer exists in the composition.
 */
function ensureFreehandLayer(state: DuiReducerState): FreehandLayer {
  let layer: FreehandLayer | undefined
  if (state.activeStrokeLayerId) {
    layer = state.composition.layers.find(
      (l) => l.id === state.activeStrokeLayerId && l.type === 'freehand'
    ) as FreehandLayer | undefined
  }

  if (!layer) {
    // Find last unlocked freehand layer or create one
    const existing = state.composition.layers
      .slice()
      .reverse()
      .find((l) => l.type === 'freehand' && !l.locked) as FreehandLayer | undefined

    if (existing) {
      layer = existing
      state.activeStrokeLayerId = existing.id
    } else {
      const newLayer: FreehandLayer = {
        id: `live_freehand_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
        name: 'Freehand Spray',
        type: 'freehand',
        visible: true,
        locked: false,
        opacity: 1.0,
        brushStyle: 'spray',
        strokes: [],
      }
      state.composition.layers.push(newLayer)
      state.activeStrokeLayerId = newLayer.id
      layer = newLayer
    }
  }

  return layer
}

function pushUndoSnapshot(state: DuiReducerState) {
  state.undoStack.push(cloneComposition(state.composition))
  if (state.undoStack.length > 50) {
    state.undoStack.shift()
  }
  state.redoStack = []
  state.revision++
}

/**
 * Authoritative DUI state reducer that processes incoming messages and updates state deterministically.
 */
export function reduceDuiMessage(state: DuiReducerState, message: DuiMessage): {
  needsFullRedraw: boolean
  liveStrokeSegment?: { stroke: FreehandStroke; isErase: boolean; points: StrokePoint[] }
  canvasResized?: { width: number; height: number }
} {
  if (!message || typeof message !== 'object') {
    return { needsFullRedraw: false }
  }

  // Queue messages if not ready and action is not 'init'
  if (!state.isReady && message.action !== 'init') {
    state.messageQueue.push(message)
    return { needsFullRedraw: false }
  }

  switch (message.action) {
    case 'init': {
      state.isReady = true
      const w = Number(message.width) || state.width || 1024
      const h = Number(message.height) || state.height || 1024
      const resized = state.width !== w || state.height !== h
      state.width = w
      state.height = h
      state.composition.width = w
      state.composition.height = h

      // Process any queued messages
      let fullRedraw = true
      while (state.messageQueue.length > 0) {
        const next = state.messageQueue.shift()!
        const res = reduceDuiMessage(state, next)
        if (res.needsFullRedraw) fullRedraw = true
      }

      return {
        needsFullRedraw: fullRedraw,
        canvasResized: resized ? { width: w, height: h } : undefined,
      }
    }

    case 'loadPaintingDocument': {
      pushUndoSnapshot(state)
      state.composition = normalizeIncomingDocument(
        message.document || message.strokes,
        state.width,
        state.height
      )
      state.width = state.composition.width || state.width
      state.height = state.composition.height || state.height
      state.activeStroke = null
      state.activeStrokeLayerId = null
      state.previewImage = null
      state.preImageSnapshot = null
      return { needsFullRedraw: true }
    }

    case 'loadStrokes': {
      if (message.append === true) {
        // Appending remote delta strokes without replacing existing work
        const appendDoc = normalizeIncomingDocument(
          message.strokes,
          state.width,
          state.height
        )

        pushUndoSnapshot(state)
        // Append layers from incoming document
        if (appendDoc.layers && appendDoc.layers.length > 0) {
          for (const newLayer of appendDoc.layers) {
            state.composition.layers.push(newLayer)
          }
        }
        if (appendDoc.eraseMask && appendDoc.eraseMask.length > 0) {
          state.composition.eraseMask = state.composition.eraseMask || []
          for (const em of appendDoc.eraseMask) {
            state.composition.eraseMask.push(em)
          }
        }
        return { needsFullRedraw: true }
      } else {
        // Full load replacement
        pushUndoSnapshot(state)
        state.composition = normalizeIncomingDocument(
          message.strokes,
          state.width,
          state.height
        )
        state.width = state.composition.width || state.width
        state.height = state.composition.height || state.height
        state.activeStroke = null
        state.activeStrokeLayerId = null
        return { needsFullRedraw: true }
      }
    }

    case 'startStroke': {
      const isErase = message.type === 'erase'
      const startPt: StrokePoint = {
        x: Number(message.x) || 0,
        y: Number(message.y) || 0,
        pressure: Number(message.pressure) || 0.85,
      }

      state.activeStroke = {
        type: isErase ? 'erase' : 'paint',
        style: message.style || 'spray',
        color: normalizeColor(message.color, '#D6FF62'),
        size: Math.max(1, Number(message.size) || 14),
        density: Number(message.density) || 25,
        pressure: Number(message.pressure) || 0.85,
        scatter: Number(message.scatter) || 1.0,
        points: [startPt],
      }

      return {
        needsFullRedraw: false,
        liveStrokeSegment: {
          stroke: state.activeStroke,
          isErase,
          points: [startPt],
        },
      }
    }

    case 'addPoint': {
      if (!state.activeStroke) return { needsFullRedraw: false }

      const pt: StrokePoint = {
        x: Number(message.x) || 0,
        y: Number(message.y) || 0,
        pressure: Number(message.pressure) || 0.85,
      }

      const prevPt =
        state.activeStroke.points[state.activeStroke.points.length - 1] || pt
      state.activeStroke.points.push(pt)

      return {
        needsFullRedraw: false,
        liveStrokeSegment: {
          stroke: state.activeStroke,
          isErase: state.activeStroke.type === 'erase',
          points: [prevPt, pt],
        },
      }
    }

    case 'endStroke': {
      if (state.activeStroke) {
        pushUndoSnapshot(state)
        const targetLayer = ensureFreehandLayer(state)
        targetLayer.strokes.push(state.activeStroke)
        state.activeStroke = null
        return { needsFullRedraw: true }
      }
      return { needsFullRedraw: false }
    }

    case 'drawStroke': {
      if (message.stroke && typeof message.stroke === 'object') {
        pushUndoSnapshot(state)
        const targetLayer = ensureFreehandLayer(state)
        targetLayer.strokes.push(message.stroke)
        return { needsFullRedraw: true }
      }
      return { needsFullRedraw: false }
    }

    case 'stampStencil': {
      pushUndoSnapshot(state)
      const stencilLayer: StencilLayer = {
        id: `stencil_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`,
        name: `Stencil Stamp`,
        type: 'stencil',
        visible: true,
        locked: false,
        opacity: 1.0,
        stencilId: message.stencilId || 'Peak',
        x: Number(message.x) || 512,
        y: Number(message.y) || 512,
        size: Number(message.size) || 70,
        rotation: Number(message.rotation) || 0,
        color: normalizeColor(message.color, '#D6FF62'),
      }
      state.composition.layers.push(stencilLayer)
      return { needsFullRedraw: true }
    }

    case 'addImage': {
      // Begin image preview: snapshot committed state
      if (!state.preImageSnapshot) {
        state.preImageSnapshot = cloneComposition(state.composition)
      }
      const img = message.image || {}
      state.previewImage = {
        id: 'preview_img_layer',
        name: 'Image Preview',
        type: 'image',
        visible: true,
        locked: false,
        opacity: 1.0,
        url: typeof img.url === 'string' ? img.url : '',
        dataUrl: typeof img.dataUrl === 'string' ? img.dataUrl : undefined,
        x: Number(img.x) || 512,
        y: Number(img.y) || 512,
        width: Number(img.width) || 256,
        height: Number(img.height) || 256,
        rotation: Number(img.rotation) || 0,
        flipX: Boolean(img.flipX),
        flipY: Boolean(img.flipY),
        filters: img.filters || {
          brightness: 0,
          contrast: 0,
          monochrome: false,
          blur: 0,
          removeBg: false,
          removeBgThreshold: 25,
        },
      }
      // Temporarily insert or replace preview layer in composition
      const existingIdx = state.composition.layers.findIndex(
        (l) => l.id === 'preview_img_layer'
      )
      if (existingIdx !== -1) {
        state.composition.layers[existingIdx] = state.previewImage
      } else {
        state.composition.layers.push(state.previewImage)
      }
      return { needsFullRedraw: true }
    }

    case 'updateImage': {
      if (state.previewImage && message.image) {
        const img = message.image
        if (img.x !== undefined) state.previewImage.x = Number(img.x)
        if (img.y !== undefined) state.previewImage.y = Number(img.y)
        if (img.width !== undefined) state.previewImage.width = Number(img.width)
        if (img.height !== undefined) state.previewImage.height = Number(img.height)
        if (img.rotation !== undefined) state.previewImage.rotation = Number(img.rotation)
        if (img.flipX !== undefined) state.previewImage.flipX = Boolean(img.flipX)
        if (img.flipY !== undefined) state.previewImage.flipY = Boolean(img.flipY)
        if (img.filters !== undefined) state.previewImage.filters = img.filters
        return { needsFullRedraw: true }
      }
      return { needsFullRedraw: false }
    }

    case 'commitImage': {
      if (state.previewImage && state.preImageSnapshot) {
        // Commit image as a permanent layer; undo stack gets the state before image was added!
        state.undoStack.push(state.preImageSnapshot)
        if (state.undoStack.length > 50) {
          state.undoStack.shift()
        }
        state.redoStack = []
        state.revision++

        const permanentId = `img_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`
        const finalLayer: ImageLayer = {
          ...state.previewImage,
          id: permanentId,
          name: 'Placed Image',
        }
        const prevIdx = state.composition.layers.findIndex(
          (l) => l.id === 'preview_img_layer'
        )
        if (prevIdx !== -1) {
          state.composition.layers[prevIdx] = finalLayer
        } else {
          state.composition.layers.push(finalLayer)
        }
        state.previewImage = null
        state.preImageSnapshot = null
        return { needsFullRedraw: true }
      }
      return { needsFullRedraw: false }
    }

    case 'cancelImage': {
      if (state.preImageSnapshot) {
        // Revert cleanly to committed state before image placement
        state.composition = cloneComposition(state.preImageSnapshot)
        state.previewImage = null
        state.preImageSnapshot = null
        return { needsFullRedraw: true }
      }
      return { needsFullRedraw: false }
    }

    case 'undo': {
      if (state.activeStroke) {
        // Discard active stroke
        state.activeStroke = null
        return { needsFullRedraw: true }
      }
      if (state.undoStack.length > 0) {
        state.redoStack.push(cloneComposition(state.composition))
        state.composition = state.undoStack.pop()!
        state.revision++
        return { needsFullRedraw: true }
      }
      return { needsFullRedraw: false }
    }

    case 'redo': {
      if (state.redoStack.length > 0) {
        state.undoStack.push(cloneComposition(state.composition))
        state.composition = state.redoStack.pop()!
        state.revision++
        return { needsFullRedraw: true }
      }
      return { needsFullRedraw: false }
    }

    case 'clear': {
      pushUndoSnapshot(state)
      state.composition.layers = []
      state.composition.eraseMask = []
      state.activeStroke = null
      state.activeStrokeLayerId = null
      state.previewImage = null
      state.preImageSnapshot = null
      return { needsFullRedraw: true }
    }

    default: {
      if ((globalThis as any).process?.env?.NODE_ENV === 'development') {
        console.warn(`[DUI] Unsupported action: ${message.action}`)
      }
      return { needsFullRedraw: false }
    }
  }
}
