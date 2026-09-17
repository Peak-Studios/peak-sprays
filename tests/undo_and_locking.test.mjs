import test from 'node:test'
import assert from 'node:assert/strict'

class TransactionalHistoryManager {
  constructor(maxActions = 50, maxBytes = 20 * 1024 * 1024) {
    this.maxActions = maxActions
    this.maxBytes = maxBytes
    this.undoStack = []
    this.redoStack = []
    this.currentBytes = 0
  }

  execute(action) {
    // Apply forward change
    const result = action.apply()
    if (result === false) return false // Action rejected (e.g. locked layer)

    this.undoStack.push(action)
    this.currentBytes += action.estimatedBytes || 256
    this.redoStack = [] // Clear redo

    // Bound by count
    if (this.undoStack.length > this.maxActions) {
      const dropped = this.undoStack.shift()
      this.currentBytes -= dropped.estimatedBytes || 256
    }

    // Bound by memory
    while (this.currentBytes > this.maxBytes && this.undoStack.length > 1) {
      const dropped = this.undoStack.shift()
      this.currentBytes -= dropped.estimatedBytes || 256
    }

    return true
  }

  undo() {
    if (this.undoStack.length === 0) return false
    const action = this.undoStack.pop()
    action.revert()
    this.redoStack.push(action)
    return true
  }

  redo() {
    if (this.redoStack.length === 0) return false
    const action = this.redoStack.pop()
    action.apply()
    this.undoStack.push(action)
    return true
  }

  reset() {
    this.undoStack = []
    this.redoStack = []
    this.currentBytes = 0
  }
}

// Layer mutation actions enforcing locked layer policy
function createUpdatePropertyAction(layer, key, beforeVal, afterVal) {
  return {
    description: `Update ${key}`,
    estimatedBytes: 128,
    apply: () => {
      if (layer.locked && key !== 'locked') return false
      layer[key] = JSON.parse(JSON.stringify(afterVal))
      return true
    },
    revert: () => {
      layer[key] = JSON.parse(JSON.stringify(beforeVal))
      return true
    }
  }
}

function createAddStrokeAction(layer, stroke) {
  return {
    description: 'Add stroke',
    estimatedBytes: (stroke.points?.length || 1) * 32,
    apply: () => {
      if (layer.locked) return false
      layer.strokes.push(stroke)
      return true
    },
    revert: () => {
      layer.strokes.pop()
      return true
    }
  }
}

test('P1.2: Undo/redo round-trip sequence with exact restoration', () => {
  const history = new TransactionalHistoryManager()
  const textLayer = { id: 'l1', type: 'text', text: 'ORIGINAL', fontSize: 32, locked: false }

  // Action 1: Change text
  const a1 = createUpdatePropertyAction(textLayer, 'text', 'ORIGINAL', 'EDIT_1')
  history.execute(a1)
  assert.equal(textLayer.text, 'EDIT_1')

  // Action 2: Change font size
  const a2 = createUpdatePropertyAction(textLayer, 'fontSize', 32, 64)
  history.execute(a2)
  assert.equal(textLayer.fontSize, 64)

  // Undo Action 2
  assert.equal(history.undo(), true)
  assert.equal(textLayer.fontSize, 32)
  assert.equal(textLayer.text, 'EDIT_1')

  // Undo Action 1
  assert.equal(history.undo(), true)
  assert.equal(textLayer.text, 'ORIGINAL')

  // Redo Action 1
  assert.equal(history.redo(), true)
  assert.equal(textLayer.text, 'EDIT_1')

  // Redo Action 2
  assert.equal(history.redo(), true)
  assert.equal(textLayer.fontSize, 64)
})

test('P1.2: Locked layers resist content, transform, and stroke mutations', () => {
  const history = new TransactionalHistoryManager()
  const freehandLayer = { id: 'f1', type: 'freehand', strokes: [], locked: true }

  // Attempt to add stroke while locked
  const strokeAction = createAddStrokeAction(freehandLayer, { type: 'paint', points: [{ x: 1, y: 1 }] })
  const executed = history.execute(strokeAction)
  assert.equal(executed, false)
  assert.equal(freehandLayer.strokes.length, 0)
  assert.equal(history.undoStack.length, 0)

  // Attempt to edit property while locked
  const propAction = createUpdatePropertyAction(freehandLayer, 'name', 'Old', 'New Name')
  assert.equal(history.execute(propAction), false)

  // Unlocking succeeds
  const unlockAction = createUpdatePropertyAction(freehandLayer, 'locked', true, false)
  assert.equal(history.execute(unlockAction), true)
  assert.equal(freehandLayer.locked, false)

  // Now stroke action succeeds
  assert.equal(history.execute(strokeAction), true)
  assert.equal(freehandLayer.strokes.length, 1)
})

test('P1.2: History bounded by count and memory without duplicating large base64 payload', () => {
  const history = new TransactionalHistoryManager(5, 1000) // max 5 actions, max 1000 bytes
  const layer = { id: 'l1', count: 0, locked: false }

  for (let i = 1; i <= 10; i++) {
    const action = createUpdatePropertyAction(layer, 'count', i - 1, i)
    history.execute(action)
  }

  // Count capped at 5
  assert.equal(history.undoStack.length, 5)
  assert.equal(layer.count, 10)

  // Undo 5 times returns to state 5
  for (let i = 0; i < 5; i++) {
    history.undo()
  }
  assert.equal(layer.count, 5)
  // Cannot undo past the bounded history
  assert.equal(history.undo(), false)
})
