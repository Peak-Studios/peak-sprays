/**
 * Mulberry32 deterministic pseudo-random number generator.
 * Produces a stable [0, 1) float from an integer or string seed.
 */
export function createSeededRandom(seed: number | string): () => number {
  let s = 0
  if (typeof seed === 'number') {
    s = seed >>> 0
  } else if (typeof seed === 'string') {
    for (let i = 0; i < seed.length; i++) {
      s = (s * 31 + seed.charCodeAt(i)) >>> 0
    }
  }

  return function next(): number {
    let t = (s += 0x6d2b79f5)
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
