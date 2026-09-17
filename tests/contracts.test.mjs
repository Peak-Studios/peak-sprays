import test from 'node:test'
import assert from 'node:assert/strict'

// Test fixture simulating exact Lua library response shape from server/designs.lua
const mockLuaLibraryResponse = {
  drafts: [],
  saved: [
    {
      id: 101,
      identifier: 'citizen:player1',
      playerName: 'John Doe',
      title: 'My Custom Tag',
      category: 'saved',
      variant: 'default',
      gangId: null,
      isServerTemplate: false,
      thumbnail: 'data:image/jpeg;base64,thumb101',
      layerCount: 2,
      createdAt: '2026-09-17 10:00:00',
      updatedAt: '2026-09-17 10:05:00',
      composition: {
        version: '1.0.0',
        title: 'My Custom Tag',
        width: 1024,
        height: 1024,
        background: 'transparent',
        layers: [
          {
            id: 'layer_1',
            name: 'Base Spray',
            type: 'freehand',
            visible: true,
            locked: false,
            opacity: 1.0,
            brushStyle: 'spray',
            strokes: []
          },
          {
            id: 'layer_2',
            name: 'Tag Text',
            type: 'text',
            visible: true,
            locked: false,
            opacity: 1.0,
            text: 'DOPE',
            font: 'Rock Salt',
            fontSize: 72,
            fontWeight: 'bold',
            fontStyle: 'normal',
            letterSpacing: 2,
            lineHeight: 1.1,
            color: '#FFFFFF',
            x: 512,
            y: 512,
            rotation: 0,
            scale: 1.0,
            outline: { enabled: true, color: '#000000', width: 4 },
            shadow: { enabled: false, color: '#000000', blur: 0, offsetX: 0, offsetY: 0 },
            glow: { enabled: false, color: '#FFFFFF', blur: 0 },
            drip: { enabled: false, count: 0, length: 0, width: 0 },
            spray: { enabled: false, count: 0, spread: 0 },
            distress: { enabled: false, roughness: 0 }
          }
        ]
      }
    }
  ],
  recent: [],
  templates: [
    {
      id: 1,
      identifier: 'SERVER',
      playerName: 'Peak Studios',
      title: 'Street Rebel Tag',
      category: 'template',
      variant: 'default',
      gangId: null,
      isServerTemplate: true,
      thumbnail: null,
      layerCount: 3,
      createdAt: '2026-09-17 00:00:00',
      updatedAt: '2026-09-17 00:00:00',
      composition: {
        version: '1.0.0',
        title: 'Street Rebel Tag',
        width: 1024,
        height: 1024,
        background: 'transparent',
        layers: [
          {
            id: 'tpl_layer_1',
            name: 'Splatter',
            type: 'freehand',
            visible: true,
            locked: false,
            opacity: 0.85,
            brushStyle: 'splatter',
            strokes: []
          }
        ]
      }
    }
  ],
  gang: [
    {
      id: 50,
      identifier: 'citizen:other_leader',
      playerName: 'Boss Marcus',
      title: '[Families] Grove Pride',
      category: 'gang',
      variant: 'official',
      gangId: 'families',
      isServerTemplate: false,
      thumbnail: null,
      layerCount: 1,
      createdAt: '2026-09-17 08:00:00',
      updatedAt: '2026-09-17 08:30:00',
      composition: {
        version: '1.0.0',
        title: '[Families] Grove Pride',
        width: 1024,
        height: 1024,
        background: 'transparent',
        layers: [
          {
            id: 'gang_l1',
            name: 'Grove Tag',
            type: 'text',
            visible: true,
            locked: false,
            opacity: 1.0,
            text: 'GSF 4 LIFE',
            font: 'Nosifer',
            fontSize: 80,
            color: '#10B981'
          }
        ]
      }
    }
  ],
  playerGang: {
    id: 'families',
    name: 'families',
    label: 'The Families',
    isBoss: false,
    grade: 1
  },
  playerIdentifier: 'citizen:player1'
}

// Logic under test: openDesign boundary
function normalizeComposition(rawComp) {
  if (!rawComp || typeof rawComp !== 'object') {
    throw new Error('Composition must be an object')
  }

  const width = typeof rawComp.width === 'number' && rawComp.width >= 256 && rawComp.width <= 2048 ? rawComp.width : 1024
  const height = typeof rawComp.height === 'number' && rawComp.height >= 256 && rawComp.height <= 2048 ? rawComp.height : 1024
  const title = typeof rawComp.title === 'string' && rawComp.title.trim() ? rawComp.title.trim() : 'Untitled Tag'
  const background = typeof rawComp.background === 'string' ? rawComp.background : 'transparent'
  const layers = Array.isArray(rawComp.layers) ? rawComp.layers.map(l => ({ ...l })) : []

  return {
    version: '1.0.0',
    title,
    width,
    height,
    background,
    layers
  }
}

class StudioDocumentManager {
  constructor(playerIdentifier) {
    this.playerIdentifier = playerIdentifier
    this.composition = {
      version: '1.0.0',
      title: 'New Tag',
      width: 1024,
      height: 1024,
      background: 'transparent',
      layers: []
    }
    this.activeRecordId = null
    this.activeRecordMetadata = null
    this.lastError = null
  }

  openDesign(record, options = {}) {
    this.lastError = null

    if (!record || typeof record !== 'object') {
      this.lastError = 'Invalid design record'
      return false
    }

    // Extract composition: support both nested record.composition and standalone composition
    const compSource = record.composition || (record.layers ? record : null)
    if (!compSource) {
      this.lastError = 'Record missing composition data'
      return false
    }

    let normalized
    try {
      normalized = normalizeComposition(compSource)
    } catch (err) {
      this.lastError = `Corrupted composition: ${err.message}`
      return false // Work intact!
    }

    // Determine ownership & forking
    const isServerTemplate = record.isServerTemplate === true || record.category === 'template'
    const isOwner = record.identifier === this.playerIdentifier && !isServerTemplate
    const canEditTemplate = options.allowTemplateEdit && isServerTemplate

    if (isOwner || canEditTemplate) {
      // Preserve update identity
      this.activeRecordId = typeof record.id === 'number' ? record.id : null
      this.activeRecordMetadata = {
        id: this.activeRecordId,
        identifier: record.identifier,
        category: record.category || 'saved',
        variant: record.variant || 'default',
        isOwner: true,
        isServerTemplate: isServerTemplate
      }
    } else {
      // FORK to new personal design!
      this.activeRecordId = null
      this.activeRecordMetadata = {
        id: null,
        identifier: this.playerIdentifier,
        category: 'saved',
        variant: 'default',
        isOwner: false, // forked
        isServerTemplate: false,
        forkedFromId: record.id,
        forkedFromTitle: record.title
      }
    }

    this.composition = normalized
    return true
  }

  getSavePayload(category = 'saved', variant = 'default') {
    return {
      id: this.activeRecordId, // null if forked, number if updating owned
      title: this.composition.title,
      category: this.activeRecordMetadata?.isOwner ? (this.activeRecordMetadata.category || category) : category,
      variant: variant,
      composition: this.composition
    }
  }
}

test('P0.1: Reading counts and thumbnails from library record envelope', () => {
  const savedRecord = mockLuaLibraryResponse.saved[0]
  assert.equal(savedRecord.layerCount, 2)
  assert.equal(savedRecord.thumbnail, 'data:image/jpeg;base64,thumb101')
  assert.equal(savedRecord.composition.layers.length, 2)
})

test('P0.1: Save -> close -> reopen owned design preserves update identity', () => {
  const manager = new StudioDocumentManager('citizen:player1')
  const ownedRecord = mockLuaLibraryResponse.saved[0]

  const ok = manager.openDesign(ownedRecord)
  assert.equal(ok, true)
  assert.equal(manager.activeRecordId, 101)
  assert.equal(manager.composition.title, 'My Custom Tag')

  // Edit design
  manager.composition.title = 'Updated Tag Title'
  const savePayload = manager.getSavePayload()

  // Must target existing row 101
  assert.equal(savePayload.id, 101)
  assert.equal(savePayload.title, 'Updated Tag Title')
})

test('P0.1: Opening server template forks to new personal design without overwriting template', () => {
  const manager = new StudioDocumentManager('citizen:player1')
  const templateRecord = mockLuaLibraryResponse.templates[0]

  const ok = manager.openDesign(templateRecord)
  assert.equal(ok, true)
  // Must NOT hold template ID 1
  assert.equal(manager.activeRecordId, null)
  assert.equal(manager.activeRecordMetadata.isOwner, false)
  assert.equal(manager.activeRecordMetadata.forkedFromId, 1)

  // Editing and saving must target a NEW row (id = null)
  manager.composition.title = 'My Forked Rebel Tag'
  const savePayload = manager.getSavePayload()
  assert.equal(savePayload.id, null)
  assert.equal(savePayload.category, 'saved')
})

test('P0.1: Opening another player\'s gang design forks to personal design for non-boss', () => {
  const manager = new StudioDocumentManager('citizen:player1')
  const gangRecord = mockLuaLibraryResponse.gang[0] // Owned by citizen:other_leader

  const ok = manager.openDesign(gangRecord)
  assert.equal(ok, true)
  assert.equal(manager.activeRecordId, null)
  assert.equal(manager.activeRecordMetadata.isOwner, false)

  const savePayload = manager.getSavePayload()
  assert.equal(savePayload.id, null)
})

test('P0.1: Corrupted or invalid composition data leaves current work intact with actionable error', () => {
  const manager = new StudioDocumentManager('citizen:player1')
  // Initial document
  manager.composition = {
    version: '1.0.0',
    title: 'Current Masterpiece',
    width: 1024,
    height: 1024,
    background: 'transparent',
    layers: [{ id: 'keep_me', name: 'Safe Layer', type: 'freehand', visible: true, locked: false, opacity: 1, strokes: [] }]
  }

  const malformedRecord = {
    id: 999,
    title: 'Corrupted Tag',
    composition: 'NOT_A_VALID_OBJECT_OR_MALFORMED'
  }

  const ok = manager.openDesign(malformedRecord)
  assert.equal(ok, false)
  assert.match(manager.lastError, /Corrupted composition|Invalid design/i)

  // Verify current work was NOT destroyed
  assert.equal(manager.composition.title, 'Current Masterpiece')
  assert.equal(manager.composition.layers.length, 1)
  assert.equal(manager.composition.layers[0].id, 'keep_me')
})
