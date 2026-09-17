import test from 'node:test'
import assert from 'node:assert/strict'
import { createLuaEnvironment } from './harness/luaRunner.mjs'

test('Server Authority & Idempotency: Production server/manager.lua under wasmoon', async (t) => {
  const env = await createLuaEnvironment({ debug: true })
  const { lua, loadFile, callbacks, clientEventsSent, dbState, setLuaGlobalJson, invokeCallback } = env

  // Load dependencies: utils, custom hooks, manager, designs
  await loadFile('shared/utils.lua')
  await loadFile('server/custom.lua')

  // Mock initial SQL tables in dbState
  dbState.paintings.set(42, {
    id: 42,
    identifier: 'license:original_artist',
    creator_name: 'OriginalArtist',
    world_x: 100.0,
    world_y: 200.0,
    world_z: 30.0,
    normal_x: 0.0,
    normal_y: 1.0,
    normal_z: 0.0,
    width: 2.0,
    height: 2.0,
    stroke_data: JSON.stringify({
      version: '1.0.0',
      documentType: 'layered',
      composition: {
        version: '1.0.0',
        title: 'Masterpiece',
        width: 1024,
        height: 1024,
        layers: [
          {
            id: 'layer-base',
            type: 'freehand',
            opacity: 1.0,
            strokes: [
              { brush: 'spray', color: '#ff0000', size: 10, points: [{ x: 10, y: 10 }] }
            ]
          }
        ]
      },
      eraseMask: []
    }),
    stroke_count: 1,
    created_at: '2026-09-17 12:00:00',
    expires_at: null
  })

  // Hook MySQL operations to dbState
  lua.global.set('__mysql_query', (query, params, cb) => {
    let result = []
    if (query.includes('SELECT * FROM spray_paintings')) {
      result = Array.from(dbState.paintings.values())
    } else if (query.includes('SELECT stroke_data FROM spray_paintings WHERE id = @id')) {
      const p = dbState.paintings.get(params?.['@id'])
      if (p) result = [{ stroke_data: p.stroke_data }]
    }
    if (typeof cb === 'function') cb(result)
    return result
  })

  lua.global.set('__mysql_insert', (query, params, cb) => {
    const id = ++dbState.lastInsertId
    if (query.includes('INSERT INTO spray_paintings')) {
      dbState.paintings.set(id, {
        id,
        identifier: params?.['@identifier'],
        player_name: params?.['@player_name'],
        world_x: params?.['@world_x'],
        world_y: params?.['@world_y'],
        world_z: params?.['@world_z'],
        stroke_data: params?.['@stroke_data'],
        stroke_count: params?.['@stroke_count'],
        corners: params?.['@corners']
      })
    }
    if (typeof cb === 'function') cb(id)
    return id
  })

  lua.global.set('__mysql_update', (query, params, cb) => {
    let affected = 0
    if (query.includes('DELETE FROM spray_paintings WHERE id = @id')) {
      const id = params?.['@id']
      if (dbState.paintings.delete(id)) affected = 1
    } else if (query.includes('UPDATE spray_paintings')) {
      const id = params?.['@id']
      const p = dbState.paintings.get(id)
      if (p) {
        p.stroke_data = params['@stroke_data']
        p.stroke_count = params['@stroke_count']
        affected = 1
      }
    }
    if (typeof cb === 'function') cb(affected)
    return affected
  })

  // Load server/manager.lua and server/designs.lua in order
  await loadFile('server/manager.lua')
  await loadFile('server/designs.lua')

  await t.test('1. Peak.Server.ValidateDocument validates safe boundaries and rejects anomalies', async () => {
    const validDoc = {
      version: '1.0.0',
      documentType: 'layered',
      composition: {
        version: '1.0.0',
        title: 'Safe',
        width: 1024,
        height: 1024,
        layers: [
          {
            id: 'l1',
            type: 'freehand',
            opacity: 1.0,
            strokes: [
              { brush: 'marker', color: '#123456', size: 5, points: [{ x: 50, y: 50 }] }
            ]
          }
        ]
      },
      eraseMask: []
    }

    await setLuaGlobalJson('testDoc', validDoc)
    const validRes = await lua.doString('local ok, err = Peak.Server.ValidateDocument(testDoc); if not ok then print("VALIDATION_ERROR: " .. tostring(err)) end; return ok')
    assert.equal(validRes, true, 'Valid document should pass server validation')

    // Test rejection of invalid layer opacity
    const badOpacityDoc = JSON.parse(JSON.stringify(validDoc))
    badOpacityDoc.composition.layers[0].opacity = 2.5
    await setLuaGlobalJson('testBadOpacityDoc', badOpacityDoc)
    const badOpacityRes = await lua.doString('local ok, err = Peak.Server.ValidateDocument(testBadOpacityDoc); return ok')
    assert.equal(badOpacityRes, false, 'Invalid layer opacity should fail server validation')

    // Test rejection of invalid eraseMask
    const badEraseDoc = JSON.parse(JSON.stringify(validDoc))
    badEraseDoc.eraseMask = [{ size: -1, points: [] }]
    await setLuaGlobalJson('testBadEraseDoc', badEraseDoc)
    const badEraseRes = await lua.doString('local ok, err = Peak.Server.ValidateDocument(testBadEraseDoc); return ok')
    assert.equal(badEraseRes, false, 'Invalid eraseMask should fail server validation')

    // Test rejection of raster image with unapproved host
    const badHostDoc = {
      version: '1.0.0',
      documentType: 'layered',
      composition: {
        version: '1.0.0',
        width: 1024,
        height: 1024,
        layers: [
          {
            id: 'l-img',
            type: 'image',
            opacity: 1.0,
            url: 'http://malicious-site.com/exploit.png',
            x: 0,
            y: 0,
            width: 256,
            height: 256
          }
        ]
      }
    }
    await setLuaGlobalJson('testBadHostDoc', badHostDoc)
    const badHostRes = await lua.doString('local ok, err = Peak.Server.ValidateDocument(testBadHostDoc); return ok')
    assert.equal(badHostRes, false, 'Unapproved image host must be rejected by server validation')
  })

  await t.test('2. MutatePainting updates caches, DB, and broadcasts sync events atomically', async () => {
    // Prime the in-memory cache
    await lua.doString(`
      Peak.Server.KnownPaintingsCache[42] = {
        id = 42,
        world_x = 100.0, world_y = 200.0, world_z = 30.0,
        stroke_count = 1
      }
      Peak.Server.StrokeDataCache[42] = {
        version = "1.0.0",
        documentType = "legacy",
        strokes = {}
      }
    `)

    // Mutate with update
    clientEventsSent.length = 0
    await setLuaGlobalJson('testUpdatePayload', {
      strokeData: { version: '1.0.0', documentType: 'layered', composition: { title: 'Updated' }, eraseMask: [] },
      strokeCount: 5
    })
    const updOk = await lua.doString(`
      local ok, err = Peak.Server.MutatePainting("update", 42, testUpdatePayload, { source = 1, reason = "test" })
      return ok
    `)
    assert.equal(updOk, true, 'MutatePainting update should succeed')

    // Verify cache updated
    const cacheCount = await lua.doString('return Peak.Server.KnownPaintingsCache[42].stroke_count')
    assert.equal(cacheCount, 5, 'KnownPaintingsCache stroke_count should be updated')

    // Verify client broadcast
    const broadcastEvent = clientEventsSent.find(e => e.eventName === 'peak-sprays:cl:updatePainting')
    assert.ok(broadcastEvent, 'Update broadcast event must be emitted')
    assert.equal(broadcastEvent.args[0].id, 42)
    assert.equal(broadcastEvent.args[0].stroke_count, 5)

    // Mutate with delete
    clientEventsSent.length = 0
    const delOk = await lua.doString(`
      local ok, err = Peak.Server.MutatePainting("delete", 42, nil, { source = 1, reason = "test_del" })
      return ok
    `)
    assert.equal(delOk, true, 'MutatePainting delete should succeed')

    // Verify removed from cache
    const cacheAfterDel = await lua.doString('return Peak.Server.KnownPaintingsCache[42]')
    assert.equal(cacheAfterDel, null, 'KnownPaintingsCache entry must be purged')
    const strokeCacheAfterDel = await lua.doString('return Peak.Server.StrokeDataCache[42]')
    assert.equal(strokeCacheAfterDel, null, 'StrokeDataCache entry must be purged')

    // Verify delete broadcast
    const delEvent = clientEventsSent.find(e => e.eventName === 'peak-sprays:cl:removePainting')
    assert.ok(delEvent, 'Remove broadcast event must be emitted')
    assert.equal(delEvent.args[0], 42)
  })

  await t.test('3. Publication Idempotency: Duplicate requestId returns identical response without re-saving', async () => {
    let removeCount = 0
    lua.global.set('__testRemoveItem', () => { removeCount++ })
    await lua.doString(`
      function Peak.Server.RemoveItem(src, item, count)
        __testRemoveItem()
        return true
      end
    `)

    const saveCb = callbacks.get('peak-sprays:savePainting')
    assert.ok(saveCb, 'peak-sprays:savePainting callback must be registered')

    // Set player ped coords matching world position (100, 200, 30)
    lua.global.set('GetEntityCoords', () => ({ x: 100.0, y: 200.0, z: 30.0 }))

    const payload = {
      requestId: 'req-unique-999',
      strokeData: {
        version: '1.0.0',
        documentType: 'layered',
        composition: {
          version: '1.0.0',
          title: 'Idempotent Mural',
          width: 1024,
          height: 1024,
          layers: []
        },
        eraseMask: []
      },
      worldX: 100.0,
      worldY: 200.0,
      worldZ: 30.0,
      normal: { x: 0.0, y: 1.0, z: 0.0 },
      canvasWidth: 1024,
      canvasHeight: 1024,
      corners: {
        bottomLeft: { x: 99.0, y: 200.0, z: 29.0 },
        bottomRight: { x: 101.0, y: 200.0, z: 29.0 },
        topLeft: { x: 99.0, y: 200.0, z: 31.0 },
        topRight: { x: 101.0, y: 200.0, z: 31.0 }
      }
    }

    // Call 1
    const res1 = await invokeCallback('peak-sprays:savePainting', 1, payload)
    if (!res1.success) console.log('RES1_ERROR:', res1)
    assert.equal(res1.success, true, 'First save should succeed')
    const firstPaintingId = res1.id
    assert.ok(firstPaintingId, 'First save should return id')
    assert.equal(removeCount, 1, 'Item should be removed once on first publication')

    // Call 2 with identical requestId
    const res2 = await invokeCallback('peak-sprays:savePainting', 1, payload)
    assert.equal(res2.success, true, 'Duplicate save request should succeed')
    assert.equal(res2.id, firstPaintingId, 'Duplicate save must return identical id')
    assert.equal(removeCount, 1, 'Duplicate save request must NOT consume items again')
  })

  await t.test('4. Server Authoritative Cleaning: validates distance, cloth, and updates eraseMask only', async () => {
    // Setup existing painting at (100, 200, 30) in db and cache
    dbState.paintings.set(100, {
      id: 100,
      world_x: 100.0,
      world_y: 200.0,
      world_z: 30.0,
      stroke_count: 3,
      stroke_data: JSON.stringify({
        version: '1.0.0',
        documentType: 'layered',
        composition: {
          version: '1.0.0',
          title: 'Clean Target',
          width: 1024,
          height: 1024,
          layers: [
            { id: 'l1', type: 'brush', opacity: 1.0, strokes: [] }
          ]
        },
        eraseMask: []
      })
    })

    await lua.doString(`
      Peak.Server.KnownPaintingsCache[100] = {
        id = 100,
        world_x = 100.0, world_y = 200.0, world_z = 30.0,
        stroke_count = 3
      }
      Peak.Server.StrokeDataCache[100] = {
        version = "1.0.0",
        documentType = "layered",
        composition = {
          version = "1.0.0",
          title = "Clean Target",
          width = 1024,
          height = 1024,
          layers = {
            { id = "l1", type = "brush", opacity = 1.0, strokes = {} }
          }
        },
        eraseMask = {}
      }
    `)

    let clothRemoved = false
    lua.global.set('__testRemoveCloth', () => { clothRemoved = true })
    await lua.doString(`
      function Peak.Server.RemoveItem(src, item, count)
        if item == Config.ClothItem then
          __testRemoveCloth()
        end
        return true
      end
    `)

    // Proximity check: Move player ped far away
    lua.global.set('GetEntityCoords', () => ({ x: 500.0, y: 500.0, z: 30.0 }))
    const farPayload = {
      paintingId: 100,
      isFullClean: false,
      eraseStrokes: [{ brush: 'spray', size: 20, points: [{ x: 50, y: 50 }] }]
    }
    const farRes = await invokeCallback('peak-sprays:cleanPainting', 1, farPayload)
    assert.equal(farRes.success, false, 'Should fail when player is too far')
    assert.match(farRes.message, /Too far/, 'Error message should report distance failure')

    // Move player close (100.5, 200.0, 30.0)
    lua.global.set('GetEntityCoords', () => ({ x: 100.5, y: 200.0, z: 30.0 }))

    // Test partial cleaning: client attempts to send dirty layers but only eraseStrokes are applied to eraseMask
    const partialPayload = {
      paintingId: 100,
      isFullClean: false,
      eraseStrokes: [{ brush: 'spray', size: 15, points: [{ x: 10, y: 10 }, { x: 20, y: 20 }] }]
    }
    clothRemoved = false
    const partialRes = await invokeCallback('peak-sprays:cleanPainting', 1, partialPayload)
    if (!partialRes.success) console.log('PARTIAL_RES_ERROR:', partialRes)
    assert.equal(partialRes.success, true, 'Partial clean within range should succeed')
    assert.equal(partialRes.isDeleted, false, 'Partial clean should not delete painting')
    assert.equal(clothRemoved, true, 'Cloth should be consumed on successful clean')

    // Verify that server eraseMask has the new stroke and the layers were untouched
    const cachedDoc = await lua.doString('return Peak.Server.StrokeDataCache[100]')
    assert.equal(cachedDoc.eraseMask.length, 1, 'Server eraseMask should now have 1 erase stroke')
    assert.equal(cachedDoc.composition.title, 'Clean Target', 'Underlying composition was preserved')

    // Test full cleaning: isFullClean = true
    const fullPayload = {
      paintingId: 100,
      isFullClean: true
    }
    const fullRes = await invokeCallback('peak-sprays:cleanPainting', 1, fullPayload)
    assert.equal(fullRes.success, true, 'Full clean should succeed')
    assert.equal(fullRes.isDeleted, true, 'Painting should be marked deleted')

    // Verify cache has been completely cleared for painting 100
    const finalCache = await lua.doString('return Peak.Server.KnownPaintingsCache[100]')
    assert.equal(finalCache, null, 'Painting 100 should be purged from memory')
  })
})
