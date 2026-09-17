import test from 'node:test'
import assert from 'node:assert/strict'
import { createLuaEnvironment } from './harness/luaRunner.mjs'
import {
  normalizeIncomingDocument,
  convertLegacyOperationsToLayers,
} from '../ui/src/renderer/documentAdapter.ts'
import {
  createDuiReducerState,
  reduceDuiMessage,
} from '../ui/src/renderer/duiProtocol.ts'

test('P0.1 Baseline Regression: Lua-normalized legacy painting sent to real browser decoder', async () => {
  const env = await createLuaEnvironment()
  await env.loadFile('shared/utils.lua')

  env.lua.doString(`
    local legacyStrokeArray = {
      {
        type = "paint",
        style = "spray",
        color = "#D6FF62",
        size = 14,
        points = {
          { x = 100, y = 150 },
          { x = 120, y = 160 }
        }
      }
    }
    luaNormalizedDoc = SprayUtils.NormalizePaintingDocument(legacyStrokeArray)
  `)

  const luaDoc = env.lua.global.get('luaNormalizedDoc')
  assert.equal(luaDoc.documentType, 'legacy')
  assert.ok(Array.isArray(luaDoc.strokes) || typeof luaDoc.strokes === 'object')

  const transmittedDoc = JSON.parse(JSON.stringify(luaDoc))
  const decoded = normalizeIncomingDocument(transmittedDoc)

  assert.ok(decoded.layers.length > 0, 'Legacy painting must produce at least 1 layer')
  assert.equal(decoded.layers[0].type, 'freehand')
  assert.equal(decoded.layers[0].strokes.length, 1)
})

test('P0.1 Legacy semantics: old array with image and stencil operations preserve original types', () => {
  const legacyOps = [
    { type: 'paint', style: 'spray', color: '#FFFFFF', size: 10, points: [{ x: 10, y: 10 }] },
    { type: 'image', url: 'https://i.imgur.com/tag.png', x: 200, y: 200, width: 300, height: 300, rotation: 15, flipX: true },
    { type: 'stencil', stencilId: 'Star', x: 400, y: 400, size: 80, color: '#D6FF62' },
    { type: 'paint', style: 'drip', color: '#10B981', size: 12, points: [{ x: 50, y: 50 }] }
  ]

  const layers = convertLegacyOperationsToLayers(legacyOps)
  assert.equal(layers.length, 4, 'Must produce 4 layers for 4 distinct operational phases')

  assert.equal(layers[0].type, 'freehand')
  assert.equal(layers[1].type, 'image')
  assert.equal(layers[1].url, 'https://i.imgur.com/tag.png')
  assert.equal(layers[1].width, 300)
  assert.equal(layers[1].flipX, true)

  assert.equal(layers[2].type, 'stencil')
  assert.equal(layers[2].stencilId, 'Star')
  assert.equal(layers[2].size, 80)

  assert.equal(layers[3].type, 'freehand')
  assert.equal(layers[3].brushStyle, 'drip')
})

test('P0.1 Document contract: non-square dimensions and world eraseMask are preserved', () => {
  const input = {
    documentType: 'layered',
    width: 1920,
    height: 1080,
    layers: [
      { id: 'l1', name: 'Base', type: 'freehand', visible: true, locked: false, opacity: 1.0, strokes: [] }
    ],
    eraseMask: [
      { size: 25, points: [{ x: 500, y: 500 }, { x: 520, y: 520 }] }
    ]
  }

  const decoded = normalizeIncomingDocument(input)
  assert.equal(decoded.width, 1920)
  assert.equal(decoded.height, 1080)
  assert.equal(decoded.eraseMask.length, 1)
  assert.equal(decoded.eraseMask[0].size, 25)
})

test('P0.2 Protocol: Pre-init messages are queued and flushed on init', () => {
  const state = createDuiReducerState(1024, 1024)
  assert.equal(state.isReady, false)

  // Send a stroke before init
  reduceDuiMessage(state, {
    action: 'loadStrokes',
    strokes: [
      { type: 'paint', style: 'spray', color: '#D6FF62', size: 14, points: [{ x: 50, y: 50 }] }
    ]
  })

  assert.equal(state.messageQueue.length, 1, 'Message should be queued while DUI not ready')
  assert.equal(state.composition.layers.length, 0, 'No layers applied yet')

  // Send init
  const res = reduceDuiMessage(state, { action: 'init', width: 1024, height: 1024 })
  assert.equal(state.isReady, true)
  assert.equal(state.messageQueue.length, 0, 'Queue should be emptied on init')
  assert.equal(state.composition.layers.length, 1, 'Queued stroke applied upon init')
  assert.equal(res.needsFullRedraw, true)
})

test('P0.2 Protocol: Start, append, end stroke and undo/redo lifecycle', () => {
  const state = createDuiReducerState(1024, 1024)
  reduceDuiMessage(state, { action: 'init', width: 1024, height: 1024 })

  // 1. Start stroke
  const rStart = reduceDuiMessage(state, {
    action: 'startStroke',
    type: 'paint',
    style: 'spray',
    color: '#D6FF62',
    size: 14,
    x: 100,
    y: 100
  })
  assert.ok(state.activeStroke)
  assert.equal(state.activeStroke.points.length, 1)
  assert.equal(rStart.needsFullRedraw, false)
  assert.ok(rStart.liveStrokeSegment)

  // 2. Add point
  const rPoint = reduceDuiMessage(state, { action: 'addPoint', x: 105, y: 110 })
  assert.equal(state.activeStroke.points.length, 2)
  assert.equal(rPoint.needsFullRedraw, false)

  // 3. End stroke commits to layer
  const rEnd = reduceDuiMessage(state, { action: 'endStroke' })
  assert.equal(state.activeStroke, null)
  assert.equal(state.composition.layers.length, 1)
  assert.equal(state.composition.layers[0].type, 'freehand')
  assert.equal(state.composition.layers[0].strokes.length, 1)
  assert.equal(rEnd.needsFullRedraw, true)

  // 4. Undo
  reduceDuiMessage(state, { action: 'undo' })
  assert.equal(state.composition.layers.length, 0, 'Undo should revert to empty pre-stroke state')

  // 5. Redo
  reduceDuiMessage(state, { action: 'redo' })
  assert.equal(state.composition.layers.length, 1, 'Redo should restore committed stroke')
  assert.equal(state.composition.layers[0].strokes.length, 1)
})

test('P0.2 Protocol: Multiple appended remote updates (append=true) do not replace strokes', () => {
  const state = createDuiReducerState(1024, 1024)
  reduceDuiMessage(state, { action: 'init', width: 1024, height: 1024 })

  // First batch
  reduceDuiMessage(state, {
    action: 'loadStrokes',
    strokes: [
      { type: 'paint', style: 'spray', color: '#10B981', size: 10, points: [{ x: 10, y: 10 }] }
    ]
  })
  assert.equal(state.composition.layers.length, 1)
  assert.equal(state.composition.layers[0].strokes.length, 1)

  // Second appended batch (append = true)
  reduceDuiMessage(state, {
    action: 'loadStrokes',
    strokes: [
      { type: 'paint', style: 'marker_bleed', color: '#EF4444', size: 16, points: [{ x: 20, y: 20 }] }
    ],
    append: true
  })

  // Both layers must exist!
  assert.equal(state.composition.layers.length, 2, 'Appending remote updates must not wipe out prior strokes')
  assert.equal(state.composition.layers[0].strokes[0].color, '#10B981')
  assert.equal(state.composition.layers[1].strokes[0].color, '#EF4444')
})

test('P0.2 Protocol: Stencil stamping creates StencilLayer in authoritative state', () => {
  const state = createDuiReducerState(1024, 1024)
  reduceDuiMessage(state, { action: 'init', width: 1024, height: 1024 })

  reduceDuiMessage(state, {
    action: 'stampStencil',
    stencilId: 'Crown',
    x: 500,
    y: 500,
    size: 75,
    color: '#D6FF62'
  })

  assert.equal(state.composition.layers.length, 1)
  assert.equal(state.composition.layers[0].type, 'stencil')
  assert.equal(state.composition.layers[0].stencilId, 'Crown')
  assert.equal(state.composition.layers[0].size, 75)
})

test('P0.2 Protocol: Image lifecycle add -> update -> commit -> undo', () => {
  const state = createDuiReducerState(1024, 1024)
  reduceDuiMessage(state, { action: 'init', width: 1024, height: 1024 })

  // Add initial base stroke
  reduceDuiMessage(state, {
    action: 'drawStroke',
    stroke: { type: 'paint', color: '#FFFFFF', size: 10, points: [{ x: 1, y: 1 }] }
  })
  assert.equal(state.composition.layers.length, 1)

  // Start image preview
  reduceDuiMessage(state, {
    action: 'addImage',
    image: { url: 'https://i.imgur.com/test.png', x: 200, y: 200, width: 256, height: 256 }
  })
  assert.ok(state.previewImage)
  assert.equal(state.previewImage.x, 200)

  // Update image transform during move
  reduceDuiMessage(state, {
    action: 'updateImage',
    image: { x: 250, y: 260, rotation: 45 }
  })
  assert.equal(state.previewImage.x, 250)
  assert.equal(state.previewImage.rotation, 45)

  // Commit image
  reduceDuiMessage(state, { action: 'commitImage' })
  assert.equal(state.previewImage, null)
  assert.equal(state.composition.layers.length, 2)
  assert.equal(state.composition.layers[1].type, 'image')
  assert.equal(state.composition.layers[1].x, 250)

  // Undo reverts the committed image
  reduceDuiMessage(state, { action: 'undo' })
  assert.equal(state.composition.layers.length, 1, 'Undo should revert committed image')
  assert.equal(state.composition.layers[0].type, 'freehand')
})

test('P0.2 Protocol: Image lifecycle add -> update -> cancel cleanly reverts without dirtying document', () => {
  const state = createDuiReducerState(1024, 1024)
  reduceDuiMessage(state, { action: 'init', width: 1024, height: 1024 })

  // Existing artwork
  reduceDuiMessage(state, {
    action: 'drawStroke',
    stroke: { type: 'paint', color: '#FFFFFF', size: 10, points: [{ x: 1, y: 1 }] }
  })
  const preLayersCount = state.composition.layers.length

  // Add image preview and manipulate
  reduceDuiMessage(state, {
    action: 'addImage',
    image: { url: 'https://i.imgur.com/cancel.png', x: 100, y: 100, width: 200, height: 200 }
  })
  reduceDuiMessage(state, {
    action: 'updateImage',
    image: { x: 300, y: 300 }
  })

  // Cancel image
  reduceDuiMessage(state, { action: 'cancelImage' })

  assert.equal(state.previewImage, null)
  assert.equal(state.composition.layers.length, preLayersCount, 'Cancelled image must be removed completely')
  assert.equal(state.composition.layers[0].type, 'freehand')
})

test('P0.2 Protocol: Live erase stroke composite semantics and clear action', () => {
  const state = createDuiReducerState(1024, 1024)
  reduceDuiMessage(state, { action: 'init', width: 1024, height: 1024 })

  const res = reduceDuiMessage(state, {
    action: 'startStroke',
    type: 'erase',
    size: 30,
    x: 400,
    y: 400
  })

  assert.ok(res.liveStrokeSegment)
  assert.equal(res.liveStrokeSegment.isErase, true)
  assert.equal(res.liveStrokeSegment.stroke.type, 'erase')

  // Commit erase stroke
  reduceDuiMessage(state, { action: 'endStroke' })
  assert.equal(state.composition.layers.length, 1)
  assert.equal(state.composition.layers[0].strokes[0].type, 'erase')

  // Clear action
  reduceDuiMessage(state, { action: 'clear' })
  assert.equal(state.composition.layers.length, 0)

  // Undo clear restores artwork
  reduceDuiMessage(state, { action: 'undo' })
  assert.equal(state.composition.layers.length, 1)
})
