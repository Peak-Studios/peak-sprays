import test from 'node:test'
import assert from 'node:assert/strict'

class PlacementStateMachine {
  constructor(composition) {
    this.status = 'idle' // idle | studio | placing | painting | publishing
    this.composition = composition
    this.aspectRatio = (composition.width || 1024) / (composition.height || 1024)
    this.duplicateMode = false
    this.sessionId = null
    this.pendingRequest = false
    this.placedCount = 0
    this.lastError = null
  }

  openStudio() {
    if (this.status !== 'idle') return false
    this.status = 'studio'
    return true
  }

  startPlacing(duplicateMode = false) {
    if (this.status !== 'studio' && this.status !== 'idle') return false
    this.status = 'placing'
    this.duplicateMode = duplicateMode
    this.sessionId = `session_${Date.now()}_${Math.random()}`
    this.pendingRequest = false
    return true
  }

  calculateDimensions(presetSize, fitMaxArea = { width: 5.0, height: 5.0 }) {
    let baseW = 1.6
    if (presetSize === 'small') baseW = 0.8
    else if (presetSize === 'medium') baseW = 1.6
    else if (presetSize === 'large') baseW = 2.5
    else if (presetSize === 'mural') baseW = 4.0
    else if (presetSize === 'fit') {
      // Fit within max area while preserving aspect ratio
      const maxW = fitMaxArea.width
      const maxH = fitMaxArea.height
      if (maxW / maxH > this.aspectRatio) {
        return { width: maxH * this.aspectRatio, height: maxH }
      } else {
        return { width: maxW, height: maxW / this.aspectRatio }
      }
    }

    const baseH = baseW / this.aspectRatio
    return { width: baseW, height: baseH }
  }

  confirmPlacement(serverCallbackSimulator) {
    if (this.status !== 'placing') return false
    if (this.pendingRequest) return false // Prevent concurrent double-placement!

    this.status = 'painting'
    this.pendingRequest = true

    // Simulate animation finishing and calling server
    this.status = 'publishing'
    const currentSession = this.sessionId

    return new Promise((resolve) => {
      serverCallbackSimulator((response) => {
        // Discard stale responses if session changed or cancelled
        if (this.sessionId !== currentSession) {
          resolve({ accepted: false, reason: 'stale_session' })
          return
        }

        this.pendingRequest = false

        if (response && response.success) {
          this.placedCount++
          if (this.duplicateMode) {
            // Stay in placing mode for next tag
            this.status = 'placing'
            resolve({ accepted: true, status: 'placing', placedCount: this.placedCount })
          } else {
            this.status = 'idle'
            resolve({ accepted: true, status: 'idle', placedCount: this.placedCount })
          }
        } else {
          this.lastError = response?.message || 'Server error'
          this.status = 'placing' // Remain placing so user can retry or adjust
          resolve({ accepted: false, error: this.lastError })
        }
      })
    })
  }

  cancel() {
    if (this.status === 'placing' || this.status === 'painting') {
      this.sessionId = null
      this.pendingRequest = false
      this.status = 'studio' // Re-open studio to not lose work
      return { action: 'return_to_studio' }
    }
    if (this.status === 'publishing') {
      // In-flight request cannot be cancelled halfway, must wait for response
      return { action: 'await_in_flight' }
    }
    this.status = 'idle'
    return { action: 'idle' }
  }
}

test('P1.3: Placement lifecycle transitions idle -> studio -> placing -> publishing -> idle', async () => {
  const comp = { width: 1024, height: 1024, layers: [] }
  const sm = new PlacementStateMachine(comp)

  assert.equal(sm.status, 'idle')
  assert.equal(sm.openStudio(), true)
  assert.equal(sm.status, 'studio')

  assert.equal(sm.startPlacing(false), true)
  assert.equal(sm.status, 'placing')

  const promise = sm.confirmPlacement((cb) => {
    setTimeout(() => cb({ success: true, id: 42 }), 10)
  })

  assert.equal(sm.status, 'publishing')
  const result = await promise
  assert.equal(result.accepted, true)
  assert.equal(result.placedCount, 1)
  assert.equal(sm.status, 'idle')
})

test('P1.3: Duplicate placement waits for server confirmation before next placement', async () => {
  const comp = { width: 1024, height: 1024, layers: [] }
  const sm = new PlacementStateMachine(comp)

  sm.openStudio()
  sm.startPlacing(true) // duplicateMode = true
  assert.equal(sm.status, 'placing')

  // Cannot confirm second placement while first is in-flight
  let respondFirst
  const firstPromise = sm.confirmPlacement((cb) => {
    respondFirst = cb
  })

  assert.equal(sm.status, 'publishing')
  assert.equal(sm.confirmPlacement(() => {}), false) // Blocked!

  // Server confirms first placement
  respondFirst({ success: true, id: 1 })
  const firstRes = await firstPromise
  assert.equal(firstRes.accepted, true)
  assert.equal(firstRes.placedCount, 1)
  assert.equal(sm.status, 'placing') // Ready for second placement!

  // Now second placement can proceed
  const secondPromise = sm.confirmPlacement((cb) => {
    cb({ success: true, id: 2 })
  })
  const secondRes = await secondPromise
  assert.equal(secondRes.placedCount, 2)
})

test('P1.3: Sizing presets and fit-wall strictly preserve aspect ratio of rectangular art', () => {
  // 16:9 banner composition (1920 x 1080)
  const banner = { width: 1920, height: 1080, layers: [] }
  const sm = new PlacementStateMachine(banner)
  const expectedRatio = 1920 / 1080

  const small = sm.calculateDimensions('small')
  assert.equal(Math.abs(small.width / small.height - expectedRatio) < 0.001, true)

  const mural = sm.calculateDimensions('mural')
  assert.equal(Math.abs(mural.width / mural.height - expectedRatio) < 0.001, true)

  const fit = sm.calculateDimensions('fit', { width: 4.0, height: 2.0 })
  assert.equal(Math.abs(fit.width / fit.height - expectedRatio) < 0.001, true)
  assert.ok(fit.width <= 4.0)
  assert.ok(fit.height <= 2.0)
})

test('P1.3: Cancellation during duplicate mode exits cleanly without invalidating committed artwork', async () => {
  const comp = { width: 1024, height: 1024, layers: [] }
  const sm = new PlacementStateMachine(comp)

  sm.openStudio()
  sm.startPlacing(true)

  // Place first spray successfully
  await sm.confirmPlacement((cb) => cb({ success: true, id: 1 }))
  assert.equal(sm.placedCount, 1)
  assert.equal(sm.status, 'placing')

  // User decides not to place second spray and presses Cancel
  const cancelRes = sm.cancel()
  assert.equal(cancelRes.action, 'return_to_studio')
  assert.equal(sm.placedCount, 1) // First spray remains committed!
  assert.equal(sm.status, 'studio')
})
