<script setup lang="ts">
import { onMounted, onUnmounted } from 'vue'
import PaintHUD from '@/components/PaintHUD.vue'
import SceneEditor from '@/components/SceneEditor.vue'
import { hudData, showHUD } from '@/store/hudState'
import { dispatchSceneAction, sceneState } from '@/store/sceneState'
import { fetchNui } from '@/utils/fetchNui'

// ─── Web Audio (spray sound) ──────────────────────────────────────────
let audioCtx:    AudioContext | null    = null
let sourceNode:  AudioBufferSourceNode | null = null
let gainNode:    GainNode | null        = null
let filterNode:  BiquadFilterNode | null = null

function stopSpraySound() {
  try {
    if (sourceNode) { sourceNode.stop(); sourceNode.disconnect(); sourceNode = null }
    if (filterNode) { filterNode.disconnect(); filterNode = null }
    if (gainNode)   { gainNode.disconnect(); gainNode = null }
  } catch (_) { /* ignore */ }
}

function startSpraySound() {
  try {
    if (!audioCtx) audioCtx = new (window.AudioContext || (window as any).webkitAudioContext)()
    if (audioCtx.state === 'suspended') audioCtx.resume()
    stopSpraySound()

    const bufLen = 2 * audioCtx.sampleRate
    const buf    = audioCtx.createBuffer(1, bufLen, audioCtx.sampleRate)
    const data   = buf.getChannelData(0)
    for (let i = 0; i < bufLen; i++) data[i] = 2 * Math.random() - 1

    sourceNode        = audioCtx.createBufferSource()
    sourceNode.buffer = buf
    sourceNode.loop   = true

    filterNode            = audioCtx.createBiquadFilter()
    filterNode.type       = 'bandpass'
    filterNode.frequency.value = 3500
    filterNode.Q.value    = 0.5    // matches original (Q=0.5)

    gainNode              = audioCtx.createGain()
    gainNode.gain.value   = 0.25   // matches original (gain=0.25)

    sourceNode.connect(filterNode)
    filterNode.connect(gainNode)
    gainNode.connect(audioCtx.destination)
    sourceNode.start(0)
  } catch (_) { /* ignore */ }
}

// ─── NUI message handler ──────────────────────────────────────────────
function onMessage(event: MessageEvent) {
  const a = event.data
  if (a?.event === 'sendAppEvent') {
    dispatchSceneAction(a.app, a.action, a.payload)
    return
  }

  if (!a || !a.action) return

  switch (a.action) {

    case 'openHUD':
      showHUD.value = true
      hudData.brushSizes          = a.brushSizes        || []
      hudData.currentBrushIndex   = a.currentBrushIndex || 0
      hudData.currentColor        = a.currentColor      || '#000000'
      hudData.forcedColor         = a.forcedColor        || null
      hudData.colorPresets        = a.colorPresets       || []
      hudData.enableColorPicker   = a.enableColorPicker  !== false
      hudData.pressure            = a.pressure           || 0.8
      hudData.density             = a.density            !== undefined ? a.density : 0.7
      hudData.pressureEnabled     = a.pressureEnabled    !== false
      hudData.keys                = a.keys               || {}
      hudData.isEraseMode         = a.isEraseMode        || false
      hudData.strokeCount         = 0
      hudData.maxStrokes          = 500
      hudData.canUndo             = false
      hudData.canRedo             = false
      hudData.importExportEnabled = a.importExportEnabled || false
      hudData.imageSpraysEnabled  = a.imageSpraysEnabled || false
      hudData.imageDefaultSize    = a.imageDefaultSize || 256
      hudData.imageMinScale       = a.imageMinScale || 0.25
      hudData.imageMaxScale       = a.imageMaxScale || 4
      hudData.activeImage         = null
      hudData.lastExportCode      = ''
      hudData.paintStyles         = a.paintStyles         || []
      hudData.currentStyleIndex   = a.currentStyleIndex   || 1
      hudData.stencils            = a.stencils            || []
      hudData.currentStencilIndex = a.currentStencilIndex || 1
      break

    case 'closeHUD':
      showHUD.value = false
      stopSpraySound()
      break

    case 'brushChanged':
      hudData.currentBrushIndex = a.brushIndex || 0
      break

    case 'styleChanged':
      hudData.currentStyleIndex = a.styleIndex || 1
      break

    case 'stencilChanged':
      hudData.currentStencilIndex = a.stencilIndex || 1
      break

    case 'strokeUpdate':
      hudData.strokeCount = a.strokeCount || 0
      hudData.maxStrokes  = a.maxStrokes  || 500
      hudData.canUndo     = a.canUndo     || false
      hudData.canRedo     = a.canRedo     || false
      break

    case 'undoRedo':
      hudData.canUndo = a.canUndo || false
      hudData.canRedo = a.canRedo || false
      break

    case 'copyToClipboard':
      if (a.text) {
        navigator.clipboard.writeText(a.text)
          .then(() => fetchNui('copyResult', { success: true }))
          .catch(() => fetchNui('copyResult', { success: false }))
      }
      break

    case 'exportResult':
      if (a.code) hudData.lastExportCode = a.code
      break

    case 'imageTransformUpdate':
      hudData.activeImage = a.image || null
      break

    case 'startSpraySound':
      startSpraySound()
      break

    case 'stopSpraySound':
      stopSpraySound()
      break
  }
}

// ─── Keyboard handler (scene creator and spray focus shortcuts) ────────
function onKeyEvent(e: KeyboardEvent) {
  const isEscape = e.key === 'Escape' || e.code === 'Escape' || e.keyCode === 27
  const isEnter  = e.key === 'Enter'  || e.code === 'Enter'  || e.keyCode === 13
  const isAlt    = e.key === 'Alt'    || e.code === 'AltLeft' || e.code === 'AltRight' || e.keyCode === 18

  if (sceneState.visible && e.type === 'keydown' && !e.repeat) {
    if (isEscape) {
      e.preventDefault()
      e.stopPropagation()
      fetchNui('sceneEditor:close')
      return
    }

    if (isEnter) {
      e.preventDefault()
      e.stopPropagation()
      fetchNui('sceneEditor:editPosition')
      return
    }
  }

  if (isEscape) {
    e.preventDefault()
    e.stopPropagation()
    fetchNui('releaseMouse')
  } else if (isAlt) {
    e.preventDefault()
    e.stopPropagation()
  }
}

onMounted(() => {
  window.addEventListener('message', onMessage)
  window.addEventListener('keydown', onKeyEvent, { capture: true })
  window.addEventListener('keyup', onKeyEvent, { capture: true })
  // Aggressively keep focus
  window.focus()
})
onUnmounted(() => {
  window.removeEventListener('message', onMessage)
  window.removeEventListener('keydown', onKeyEvent, { capture: true })
  window.removeEventListener('keyup', onKeyEvent, { capture: true })
})
</script>

<template>
  <div class="w-full h-full relative">
    <PaintHUD v-if="showHUD.value" />
    <SceneEditor />
  </div>
</template>
