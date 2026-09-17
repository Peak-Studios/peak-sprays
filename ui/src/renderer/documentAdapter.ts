import type {
  FreehandLayer,
  FreehandStroke,
  GraffitiComposition,
  GraffitiLayer,
  ImageLayer,
  StencilLayer,
  WorldEraseStroke,
} from '../types/graffiti.ts'

export class DocumentAdapterError extends Error {
  details?: any

  constructor(message: string, details?: any) {
    super(message)
    this.name = 'DocumentAdapterError'
    this.details = details
  }
}

/**
 * Converts a sequence of legacy operations into distinct typed GraffitiLayers,
 * preserving operation order, transforms, stencil stamps, and image operations.
 */
export function convertLegacyOperationsToLayers(operations: any[]): GraffitiLayer[] {
  if (!Array.isArray(operations) || operations.length === 0) {
    return [
      {
        id: 'legacy_layer_1',
        name: 'Legacy Artwork',
        type: 'freehand',
        visible: true,
        locked: false,
        opacity: 1.0,
        brushStyle: 'spray',
        strokes: [],
      },
    ]
  }

  const layers: GraffitiLayer[] = []
  let currentFreehandStrokes: FreehandStroke[] = []
  let freehandLayerIndex = 1

  function flushFreehand() {
    if (currentFreehandStrokes.length > 0) {
      layers.push({
        id: `legacy_freehand_${freehandLayerIndex++}`,
        name: `Freehand Layer ${freehandLayerIndex - 1}`,
        type: 'freehand',
        visible: true,
        locked: false,
        opacity: 1.0,
        brushStyle: (currentFreehandStrokes[0]?.style as any) || 'spray',
        strokes: currentFreehandStrokes,
      })
      currentFreehandStrokes = []
    }
  }

  for (let i = 0; i < operations.length; i++) {
    const op = operations[i]
    if (!op || typeof op !== 'object') continue

    if (op.type === 'image') {
      flushFreehand()
      const imgLayer: ImageLayer = {
        id: op.id || `legacy_img_${i + 1}`,
        name: op.name || `Imported Image ${i + 1}`,
        type: 'image',
        visible: op.visible !== false,
        locked: false,
        opacity: typeof op.opacity === 'number' ? op.opacity : 1.0,
        url: typeof op.url === 'string' ? op.url : '',
        dataUrl: typeof op.dataUrl === 'string' ? op.dataUrl : undefined,
        x: Number(op.x) || 512,
        y: Number(op.y) || 512,
        width: Number(op.width) || 256,
        height: Number(op.height) || 256,
        rotation: Number(op.rotation) || 0,
        flipX: Boolean(op.flipX),
        flipY: Boolean(op.flipY),
        filters: op.filters || {
          brightness: 0,
          contrast: 0,
          monochrome: false,
          blur: 0,
          removeBg: false,
          removeBgThreshold: 25,
        },
      }
      layers.push(imgLayer)
    } else if (op.type === 'stencil') {
      flushFreehand()
      const stencilLayer: StencilLayer = {
        id: op.id || `legacy_stencil_${i + 1}`,
        name: op.name || `Stencil (${op.stencilId || 'Stamp'})`,
        type: 'stencil',
        visible: op.visible !== false,
        locked: false,
        opacity: typeof op.opacity === 'number' ? op.opacity : 1.0,
        stencilId: op.stencilId || 'Peak',
        x: Number(op.x) || (Array.isArray(op.points) && op.points[0]?.x) || 512,
        y: Number(op.y) || (Array.isArray(op.points) && op.points[0]?.y) || 512,
        size: Number(op.size) || 70,
        rotation: Number(op.rotation) || 0,
        color: op.color || '#D6FF62',
      }
      layers.push(stencilLayer)
    } else {
      // Paint or Erase stroke
      const stroke: FreehandStroke = {
        type: op.type === 'erase' ? 'erase' : 'paint',
        style: op.style || 'spray',
        color: op.color || '#D6FF62',
        size: Number(op.size) || 14,
        points: Array.isArray(op.points) ? op.points : [],
        pressure: Number(op.pressure) || 0.85,
        density: Number(op.density) || 25,
        scatter: Number(op.scatter) || 1.0,
      }
      currentFreehandStrokes.push(stroke)
    }
  }

  flushFreehand()

  if (layers.length === 0) {
    layers.push({
      id: 'legacy_layer_1',
      name: 'Legacy Artwork',
      type: 'freehand',
      visible: true,
      locked: false,
      opacity: 1.0,
      brushStyle: 'spray',
      strokes: [],
    })
  }

  return layers
}

/**
 * Universal, versioned document adapter for Peak Sprays.
 * Normalizes all supported document variants:
 * 1. Raw numeric operation array
 * 2. Normalized legacy document { documentType: 'legacy', strokes: [...], eraseMask: [...] }
 * 3. Earlier composition wrappers { isComposition: true, composition: ... }
 * 4. Current layered documents { documentType: 'layered', composition: ... }
 * 5. Standalone GraffitiComposition
 */
export function normalizeIncomingDocument(
  rawInput: any,
  fallbackWidth = 1024,
  fallbackHeight = 1024
): GraffitiComposition {
  if (rawInput === null || rawInput === undefined) {
    return {
      version: '1.0.0',
      title: 'Empty Canvas',
      width: fallbackWidth,
      height: fallbackHeight,
      background: 'transparent',
      layers: [],
      eraseMask: [],
    }
  }

  // Handle JSON string if pre-serialized
  let data = rawInput
  if (typeof rawInput === 'string') {
    try {
      data = JSON.parse(rawInput)
    } catch (err: any) {
      throw new DocumentAdapterError(`Corrupted JSON painting payload: ${err.message}`, { rawInput })
    }
  }

  if (typeof data !== 'object') {
    throw new DocumentAdapterError('Invalid document payload: expected object or array', { data })
  }

  // Determine width and height with preservation of non-square dimensions
  const width =
    Number(data.width || data.canvas_width || data.canvasWidth || (data.composition && data.composition.width)) ||
    fallbackWidth
  const height =
    Number(data.height || data.canvas_height || data.canvasHeight || (data.composition && data.composition.height)) ||
    fallbackHeight

  const eraseMask: WorldEraseStroke[] = Array.isArray(data.eraseMask)
    ? data.eraseMask
    : data.composition && Array.isArray(data.composition.eraseMask)
      ? data.composition.eraseMask
      : []

  // Case 1: Raw numeric operation array
  if (Array.isArray(data)) {
    return {
      version: '1.0.0',
      title: 'Legacy Painting',
      width,
      height,
      background: 'transparent',
      layers: convertLegacyOperationsToLayers(data),
      eraseMask: [],
    }
  }

  // Case 2: Normalized legacy document { documentType: 'legacy', strokes: [...], eraseMask: [...] }
  if (data.documentType === 'legacy' || (data.strokes && !data.composition && !data.layers)) {
    const rawStrokes = Array.isArray(data.strokes) ? data.strokes : []
    return {
      version: data.version || '1.0.0',
      title: data.title || 'Legacy Painting',
      width,
      height,
      background: data.background || 'transparent',
      layers: convertLegacyOperationsToLayers(rawStrokes),
      eraseMask,
    }
  }

  // Case 3: Earlier composition wrapper or current layered document
  if (
    data.documentType === 'layered' ||
    data.isComposition === true ||
    data.composition !== undefined ||
    Array.isArray(data.layers)
  ) {
    const comp = data.composition || data
    const compLayers: GraffitiLayer[] = Array.isArray(comp.layers)
      ? comp.layers
      : Array.isArray(data.layers)
        ? data.layers
        : []

    return {
      version: comp.version || data.version || '1.0.0',
      title: comp.title || data.title || 'Spray',
      width: Number(comp.width) || width,
      height: Number(comp.height) || height,
      background: comp.background || 'transparent',
      layers: compLayers,
      eraseMask,
    }
  }

  // Diagnostic error for unclassifiable non-empty document rather than silent drop
  const keys = Object.keys(data)
  if (keys.length > 0) {
    throw new DocumentAdapterError('Unrecognized document structure; cannot decode safely', {
      keys,
      documentType: data.documentType,
    })
  }

  return {
    version: '1.0.0',
    title: 'DUI Painting',
    width,
    height,
    background: 'transparent',
    layers: [],
    eraseMask: [],
  }
}
