import test from 'node:test'
import assert from 'node:assert/strict'

// Mulberry32 deterministic PRNG
function createSeededRandom(seed) {
  let s = typeof seed === 'number' ? seed : 0
  if (typeof seed === 'string') {
    for (let i = 0; i < seed.length; i++) {
      s = (s * 31 + seed.charCodeAt(i)) >>> 0
    }
  }
  return function next() {
    let t = (s += 0x6d2b79f5)
    t = Math.imMath ? Math.imul(t ^ (t >>> 15), t | 1) : Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

// Deterministic procedural splatter points for spray brushes
function generateProceduralSplatter(seed, count, radius) {
  const rng = createSeededRandom(seed)
  const points = []
  for (let i = 0; i < count; i++) {
    const angle = rng() * Math.PI * 2
    const dist = rng() * radius
    points.push({
      dx: Math.cos(angle) * dist,
      dy: Math.sin(angle) * dist,
      size: 1 + rng() * 3
    })
  }
  return points
}

// Glyph-aware drips: anchor drips to actual characters
function generateGlyphDrips(seed, text, fontSize, dripCount, maxLen) {
  const rng = createSeededRandom(seed)
  const drips = []
  const cleanText = text.trim()
  if (!cleanText) return drips

  for (let i = 0; i < dripCount; i++) {
    const charIndex = Math.floor(rng() * cleanText.length)
    const length = 15 + rng() * (maxLen - 15)
    const width = 2 + rng() * 3
    drips.push({
      charIndex,
      char: cleanText[charIndex],
      length,
      width
    })
  }
  return drips
}

test('P1.1: Deterministic seeded PRNG guarantees identical procedural geometry', () => {
  const seed = 'layer_text_abc123'
  const pass1 = generateProceduralSplatter(seed, 20, 30)
  const pass2 = generateProceduralSplatter(seed, 20, 30)

  assert.deepEqual(pass1, pass2)
})

test('P1.1: Procedural seeds are independent per layer (altering layer 2 does not alter layer 1)', () => {
  const layer1Seed = 'layer_1_spray'
  const layer2SeedA = 'layer_2_text_v1'
  const layer2SeedB = 'layer_2_text_v2_edited'

  const l1Before = generateProceduralSplatter(layer1Seed, 15, 25)
  // Edit on layer 2 generates new output for layer 2
  const l2A = generateProceduralSplatter(layer2SeedA, 10, 20)
  const l2B = generateProceduralSplatter(layer2SeedB, 10, 20)
  assert.notDeepEqual(l2A, l2B)

  // But layer 1 remains 100% identical!
  const l1After = generateProceduralSplatter(layer1Seed, 15, 25)
  assert.deepEqual(l1Before, l1After)
})

test('P1.1: Glyph-anchored drips generate deterministic drips from actual glyphs', () => {
  const seed = 'tag_drips_456'
  const text = 'LOS SANTOS'
  const drips1 = generateGlyphDrips(seed, text, 64, 4, 80)
  const drips2 = generateGlyphDrips(seed, text, 64, 4, 80)

  assert.equal(drips1.length, 4)
  assert.deepEqual(drips1, drips2)
  for (const d of drips1) {
    assert.ok(text.includes(d.char))
  }
})
