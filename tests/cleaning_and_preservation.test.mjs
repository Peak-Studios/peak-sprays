import test from 'node:test'
import assert from 'node:assert/strict'

// Simulation of SprayUtils.NormalizePaintingDocument & ValidateErase logic
function normalizePaintingDocument(raw) {
  if (!raw || typeof raw !== 'object') {
    return {
      version: '1.0.0',
      documentType: 'layered',
      composition: {
        version: '1.0.0',
        title: 'Empty Spray',
        width: 1024,
        height: 1024,
        background: 'transparent',
        layers: []
      },
      eraseMask: []
    }
  }

  // Case 1: Legacy stroke array
  if (Array.isArray(raw)) {
    return {
      version: '1.0.0',
      documentType: 'legacy',
      strokes: raw,
      eraseMask: []
    }
  }

  // Case 2: v0.3.0 composition wrapper { isComposition: true, composition: { ... }, layers: [ ... ] }
  if (raw.isComposition === true || raw.composition !== undefined) {
    const comp = raw.composition || raw
    const eraseMask = Array.isArray(raw.eraseMask) ? raw.eraseMask : []
    return {
      version: '1.0.0',
      documentType: 'layered',
      composition: comp,
      eraseMask: eraseMask
    }
  }

  // Case 3: Already normalized document
  if (raw.documentType === 'layered' || raw.documentType === 'legacy') {
    return {
      version: raw.version || '1.0.0',
      documentType: raw.documentType,
      composition: raw.composition,
      strokes: raw.strokes,
      eraseMask: Array.isArray(raw.eraseMask) ? raw.eraseMask : []
    }
  }

  // Fallback safe normalization
  return {
    version: '1.0.0',
    documentType: 'layered',
    composition: {
      version: '1.0.0',
      title: 'Spray',
      width: 1024,
      height: 1024,
      background: 'transparent',
      layers: []
    },
    eraseMask: []
  }
}

class WorldEraserSession {
  constructor(initialDoc) {
    this.originalDoc = JSON.parse(JSON.stringify(initialDoc))
    this.targetDoc = normalizePaintingDocument(initialDoc)
    this.newEraseStrokes = []
    this.isSessionActive = true
  }

  addEraseStroke(stroke) {
    this.newEraseStrokes.push(stroke)
  }

  cancel() {
    this.isSessionActive = false
    // Returns original unchanged
    return {
      updated: false,
      consumedCloth: false,
      document: this.originalDoc
    }
  }

  confirm() {
    this.isSessionActive = false
    // No-op check
    if (this.newEraseStrokes.length === 0) {
      return {
        updated: false,
        consumedCloth: false,
        document: this.originalDoc,
        reason: 'no_changes'
      }
    }

    // Merge new erase strokes into the target document's eraseMask!
    const updatedDoc = JSON.parse(JSON.stringify(this.targetDoc))
    updatedDoc.eraseMask = [...(updatedDoc.eraseMask || []), ...this.newEraseStrokes]

    return {
      updated: true,
      consumedCloth: true,
      document: updatedDoc
    }
  }
}

test('P0.2: Normalizing legacy numeric stroke arrays', () => {
  const legacyStrokes = [
    { type: 'paint', color: '#FF0000', size: 10, points: [{ x: 10, y: 10 }] },
    { type: 'paint', color: '#00FF00', size: 15, points: [{ x: 20, y: 20 }] }
  ]

  const doc = normalizePaintingDocument(legacyStrokes)
  assert.equal(doc.documentType, 'legacy')
  assert.equal(doc.strokes.length, 2)
  assert.equal(Array.isArray(doc.eraseMask), true)
  assert.equal(doc.eraseMask.length, 0)
})

test('P0.2: Normalizing v0.3.0 composition wrapper without dropping layers', () => {
  const v030Wrapper = {
    isComposition: true,
    composition: {
      version: '1.0.0',
      title: 'Mural',
      width: 1024,
      height: 1024,
      layers: [
        { id: 'l1', type: 'freehand', name: 'Lines' },
        { id: 'l2', type: 'text', name: 'Text' },
        { id: 'l3', type: 'image', name: 'Image' },
        { id: 'l4', type: 'stencil', name: 'Stamp' }
      ]
    },
    layers: []
  }

  const doc = normalizePaintingDocument(v030Wrapper)
  assert.equal(doc.documentType, 'layered')
  assert.equal(doc.composition.layers.length, 4)
  assert.equal(doc.eraseMask.length, 0)
})

test('P0.2: Partially erase design with all 4 layer types preserves all layers under eraseMask', () => {
  const layeredArt = {
    documentType: 'layered',
    composition: {
      version: '1.0.0',
      title: 'Masterpiece 4 Layers',
      width: 1024,
      height: 1024,
      layers: [
        { id: 'l1', type: 'freehand', name: 'Spray', strokes: [{ type: 'paint', points: [{ x: 100, y: 100 }] }] },
        { id: 'l2', type: 'text', name: 'Graffiti Text', text: 'ROYALTY' },
        { id: 'l3', type: 'image', name: 'Logo', url: 'https://i.imgur.com/example.png' },
        { id: 'l4', type: 'stencil', name: 'Crown', stencilId: 'Crown' }
      ]
    },
    eraseMask: []
  }

  const session = new WorldEraserSession(layeredArt)
  // Simulate cleaning a section with the cloth
  session.addEraseStroke({
    type: 'world_clean',
    size: 25,
    points: [{ x: 100, y: 100 }, { x: 105, y: 105 }]
  })

  const result = session.confirm()
  assert.equal(result.updated, true)
  assert.equal(result.consumedCloth, true)
  assert.equal(result.document.eraseMask.length, 1)

  // ALL 4 layers must remain completely untouched in composition!
  assert.equal(result.document.composition.layers.length, 4)
  assert.equal(result.document.composition.layers[0].name, 'Spray')
  assert.equal(result.document.composition.layers[1].name, 'Graffiti Text')
  assert.equal(result.document.composition.layers[2].name, 'Logo')
  assert.equal(result.document.composition.layers[3].name, 'Crown')

  // Simulate reconnect/restart: reloading the document
  const reloaded = normalizePaintingDocument(result.document)
  assert.equal(reloaded.composition.layers.length, 4)
  assert.equal(reloaded.eraseMask.length, 1)
})

test('P0.2: Opening cloth interface and confirming without changes does NOT overwrite or consume item', () => {
  const layeredArt = {
    documentType: 'layered',
    composition: {
      version: '1.0.0',
      title: 'Art',
      width: 1024,
      height: 1024,
      layers: [{ id: 'l1', type: 'freehand' }]
    },
    eraseMask: []
  }

  const session = new WorldEraserSession(layeredArt)
  // No erase strokes added
  const result = session.confirm()
  assert.equal(result.updated, false)
  assert.equal(result.consumedCloth, false)
  assert.equal(result.reason, 'no_changes')
  assert.deepEqual(result.document, layeredArt)
})

test('P0.2: Cancelling eraser session preserves original document unmodified', () => {
  const layeredArt = {
    documentType: 'layered',
    composition: {
      version: '1.0.0',
      title: 'Untouched Art',
      width: 1024,
      height: 1024,
      layers: [{ id: 'l1', type: 'text', text: 'HELLO' }]
    },
    eraseMask: []
  }

  const session = new WorldEraserSession(layeredArt)
  session.addEraseStroke({ type: 'world_clean', size: 10, points: [{ x: 50, y: 50 }] })

  const result = session.cancel()
  assert.equal(result.updated, false)
  assert.equal(result.consumedCloth, false)
  assert.equal(result.document.eraseMask.length, 0)
  assert.deepEqual(result.document, layeredArt)
})
