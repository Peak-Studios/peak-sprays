import test from 'node:test'
import assert from 'node:assert/strict'

// Server policies under test
function canReadDesign(player, designRow) {
  if (!designRow) return false
  if (designRow.is_server_template === 1 || designRow.category === 'template') return true
  if (player.isAdmin) return true
  if (designRow.identifier === player.identifier) return true
  if (designRow.category === 'gang' && designRow.gang_id && player.gang && player.gang.id === designRow.gang_id) {
    return true
  }
  return false
}

function canEditDesign(player, designRow) {
  if (!designRow) return false
  if (designRow.is_server_template === 1) {
    return player.isAdmin === true
  }
  if (player.isAdmin) return true
  return designRow.identifier === player.identifier
}

function canPublishGangTemplate(player, targetGangId) {
  if (!player.gang || player.gang.id === 'none') return false
  if (targetGangId && player.gang.id !== targetGangId) return false
  if (player.isAdmin) return true
  return player.gang.isBoss === true
}

// Bounded recursive validation under test
const ALLOWED_IMAGE_HOSTS = ['i.imgur.com', 'media.discordapp.net', 'cdn.discordapp.com', 'images.unsplash.com']
const PRIVATE_IP_REGEX = /^(?:127\.|10\.|192\.168\.|172\.(?:1[6-9]|2[0-9]|3[0-1])\.|localhost)/i

function isAllowedHost(host) {
  if (!host) return false
  host = host.toLowerCase()
  if (PRIVATE_IP_REGEX.test(host)) return false
  return ALLOWED_IMAGE_HOSTS.some(allowed => host === allowed || host.endsWith('.' + allowed))
}

function validateLayer(layer, imageState = { count: 0 }) {
  if (!layer || typeof layer !== 'object') return { valid: false, error: 'Layer must be an object' }
  if (typeof layer.id !== 'string' || !layer.id) return { valid: false, error: 'Layer ID required' }
  if (typeof layer.name !== 'string' || layer.name.length > 64) return { valid: false, error: 'Invalid layer name' }
  if (!['freehand', 'text', 'image', 'stencil'].includes(layer.type)) return { valid: false, error: 'Unknown layer type' }

  // Opacity must be finite number between 0 and 1, respecting 0!
  if (typeof layer.opacity !== 'number' || !Number.isFinite(layer.opacity) || layer.opacity < 0 || layer.opacity > 1) {
    return { valid: false, error: 'Invalid layer opacity' }
  }

  if (layer.type === 'text') {
    if (typeof layer.text !== 'string' || layer.text.length > 200) return { valid: false, error: 'Text exceeds 200 characters' }
    if (typeof layer.fontSize !== 'number' || !Number.isFinite(layer.fontSize) || layer.fontSize <= 0 || layer.fontSize > 300) {
      return { valid: false, error: 'Invalid font size' }
    }
    if (typeof layer.x !== 'number' || !Number.isFinite(layer.x) || typeof layer.y !== 'number' || !Number.isFinite(layer.y)) {
      return { valid: false, error: 'Non-finite text coordinates' }
    }
  } else if (layer.type === 'image') {
    imageState.count++
    if (imageState.count > 5) return { valid: false, error: 'Too many image layers' }
    if (typeof layer.url !== 'string' || layer.url.length > 512) return { valid: false, error: 'Image URL too long or invalid' }
    if (!layer.url.startsWith('https://')) return { valid: false, error: 'Image URL must use HTTPS' }

    let host
    try {
      const u = new URL(layer.url)
      host = u.hostname
    } catch {
      return { valid: false, error: 'Malformed image URL' }
    }

    if (!isAllowedHost(host)) return { valid: false, error: 'Image host is not allowed or private address' }
  } else if (layer.type === 'freehand') {
    if (!Array.isArray(layer.strokes) || layer.strokes.length > 100) return { valid: false, error: 'Too many freehand strokes' }
    let totalPoints = 0
    for (const stroke of layer.strokes) {
      if (!Array.isArray(stroke.points) || stroke.points.length > 1000) return { valid: false, error: 'Stroke point limit exceeded' }
      totalPoints += stroke.points.length
      if (totalPoints > 5000) return { valid: false, error: 'Layer point limit exceeded' }
      for (const pt of stroke.points) {
        if (typeof pt.x !== 'number' || !Number.isFinite(pt.x) || typeof pt.y !== 'number' || !Number.isFinite(pt.y)) {
          return { valid: false, error: 'Non-finite stroke point' }
        }
      }
    }
  }

  return { valid: true }
}

function validateComposition(comp) {
  if (!comp || typeof comp !== 'object') return { valid: false, error: 'Composition must be an object' }
  const jsonStr = JSON.stringify(comp)
  if (jsonStr.length > 524288) return { valid: false, error: 'Composition exceeds 512KB limit' }

  if (typeof comp.width !== 'number' || !Number.isFinite(comp.width) || comp.width < 256 || comp.width > 2048) {
    return { valid: false, error: 'Canvas width out of bounds (256-2048)' }
  }
  if (typeof comp.height !== 'number' || !Number.isFinite(comp.height) || comp.height < 256 || comp.height > 2048) {
    return { valid: false, error: 'Canvas height out of bounds (256-2048)' }
  }
  if (comp.width * comp.height > 2048 * 2048) return { valid: false, error: 'Total canvas pixel budget exceeded' }

  if (!Array.isArray(comp.layers) || comp.layers.length > 32) {
    return { valid: false, error: 'Layer count out of bounds (max 32 layers)' }
  }

  const imageState = { count: 0 }
  for (const layer of comp.layers) {
    const res = validateLayer(layer, imageState)
    if (!res.valid) return res
  }

  return { valid: true }
}

test('P0.3: Authorization - CanReadDesign permissions', () => {
  const alice = { identifier: 'alice', isAdmin: false, gang: { id: 'families' } }
  const bob = { identifier: 'bob', isAdmin: false, gang: { id: 'ballas' } }
  const admin = { identifier: 'admin1', isAdmin: true }

  const serverTemplate = { id: 1, is_server_template: 1, category: 'template' }
  const alicePrivate = { id: 2, identifier: 'alice', is_server_template: 0, category: 'saved' }
  const familiesGang = { id: 3, identifier: 'charlie', is_server_template: 0, category: 'gang', gang_id: 'families' }

  // Server templates readable by everyone
  assert.equal(canReadDesign(alice, serverTemplate), true)
  assert.equal(canReadDesign(bob, serverTemplate), true)

  // Alice private readable by Alice and Admin, but NOT Bob
  assert.equal(canReadDesign(alice, alicePrivate), true)
  assert.equal(canReadDesign(admin, alicePrivate), true)
  assert.equal(canReadDesign(bob, alicePrivate), false)

  // Families gang design readable by Alice (same gang) and Admin, but NOT Bob (ballas)
  assert.equal(canReadDesign(alice, familiesGang), true)
  assert.equal(canReadDesign(admin, familiesGang), true)
  assert.equal(canReadDesign(bob, familiesGang), false)
})

test('P0.3: Authorization - CanEditDesign and Server Template protection', () => {
  const alice = { identifier: 'alice', isAdmin: false }
  const admin = { identifier: 'admin1', isAdmin: true }
  const serverTemplate = { id: 1, is_server_template: 1, category: 'template' }
  const aliceDoc = { id: 2, identifier: 'alice', is_server_template: 0 }

  // Alice cannot edit server template
  assert.equal(canEditDesign(alice, serverTemplate), false)
  // Admin can edit server template
  assert.equal(canEditDesign(admin, serverTemplate), true)

  // Alice can edit own design
  assert.equal(canEditDesign(alice, aliceDoc), true)
  // Non-owner cannot edit Alice's design
  assert.equal(canEditDesign({ identifier: 'bob', isAdmin: false }, aliceDoc), false)
})

test('P0.3: Authorization - Gang boss requirement for gang templates', () => {
  const boss = { identifier: 'boss', gang: { id: 'vagos', isBoss: true } }
  const member = { identifier: 'member', gang: { id: 'vagos', isBoss: false } }
  const noGang = { identifier: 'solo', gang: { id: 'none', isBoss: false } }

  assert.equal(canPublishGangTemplate(boss, 'vagos'), true)
  assert.equal(canPublishGangTemplate(member, 'vagos'), false)
  assert.equal(canPublishGangTemplate(noGang, 'vagos'), false)
  assert.equal(canPublishGangTemplate(boss, 'ballas'), false) // Cannot publish for another gang
})

test('P0.3: Validation - Reject excessive layers (> 32)', () => {
  const comp = {
    title: 'Too Many Layers',
    width: 1024,
    height: 1024,
    layers: Array.from({ length: 33 }, (_, i) => ({
      id: `layer_${i}`,
      name: `L${i}`,
      type: 'freehand',
      opacity: 1,
      strokes: []
    }))
  }

  const res = validateComposition(comp)
  assert.equal(res.valid, false)
  assert.match(res.error, /Layer count out of bounds/)
})

test('P0.3: Validation - Reject unapproved image host and private IP SSRF attempt', () => {
  const makeImageComp = (url) => ({
    title: 'Image Tag',
    width: 1024,
    height: 1024,
    layers: [
      { id: 'img1', name: 'Img', type: 'image', opacity: 1, url }
    ]
  })

  // Allowed host
  assert.equal(validateComposition(makeImageComp('https://i.imgur.com/good.png')).valid, true)

  // HTTP rejected
  assert.equal(validateComposition(makeImageComp('http://i.imgur.com/insecure.png')).valid, false)

  // Unapproved external host rejected
  assert.equal(validateComposition(makeImageComp('https://untrusted-host.com/img.png')).valid, false)

  // Localhost / private IP SSRF rejected
  assert.equal(validateComposition(makeImageComp('https://localhost:8080/secret.png')).valid, false)
  assert.equal(validateComposition(makeImageComp('https://192.168.1.1/secret.png')).valid, false)
  assert.equal(validateComposition(makeImageComp('https://127.0.0.1:3000/secret.png')).valid, false)
})

test('P0.3: Validation - Finite numeric validation and valid 0 opacity', () => {
  const validZeroOpacity = {
    title: 'Zero Opacity Valid',
    width: 1024,
    height: 1024,
    layers: [
      { id: 'l1', name: 'Transparent Layer', type: 'text', opacity: 0, text: 'Ghost', fontSize: 32, x: 0, y: 0 }
    ]
  }
  assert.equal(validateComposition(validZeroOpacity).valid, true)

  const nanOpacity = {
    title: 'NaN Opacity Invalid',
    width: 1024,
    height: 1024,
    layers: [
      { id: 'l1', name: 'Bad Layer', type: 'text', opacity: NaN, text: 'Ghost', fontSize: 32, x: 0, y: 0 }
    ]
  }
  assert.equal(validateComposition(nanOpacity).valid, false)
})
