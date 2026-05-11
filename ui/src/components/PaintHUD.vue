<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { hudData } from '@/store/hudState'
import { fetchNui } from '@/utils/fetchNui'

// ── Computed props ────────────────────────────────────────────────
const currentBrushName = computed(() => {
  const b = hudData.brushSizes[hudData.currentBrushIndex - 1]
  return b ? b.name : 'MEDIUM'
})

const accentColor = computed(() => hudData.currentColor || '#10b981')

const brushDotPx = computed(() => {
  const b = hudData.brushSizes[hudData.currentBrushIndex - 1]
  return b ? Math.min(22, Math.max(4, 1.2 * b.size)) : 8
})

const strokeRingDash = computed(() =>
  (hudData.pressure * 100.5).toFixed(1) + ' 100.5'
)

const displayPresets = computed(() => hudData.colorPresets.slice(0, 10))

// ── Density slider ───────────────────────────────────────────────────
function onDensityChange(e: Event) {
  const v = parseFloat((e.target as HTMLInputElement).value)
  hudData.density = v
  fetchNui('changeDensity', { density: v })
}

// ── Import / Export ──────────────────────────────────────────────────
const importExportCode = ref('')

function doImport() {
  const code = importExportCode.value.trim()
  if (code) fetchNui('uiImportPainting', { code })
}

function doExport() {
  fetchNui('uiExportPainting', {})
}

watch(() => hudData.lastExportCode, (v) => {
  if (v) importExportCode.value = v
})

// ── Color picker / presets ───────────────────────────────────────────
const showColorPicker = ref(false)

function selectColor(color: string) {
  hudData.currentColor = color
  fetchNui('changeColor', { color })
}
</script>

<template>
  <!-- Outer: full screen, no pointer events -->
  <div class="fixed inset-0 select-none pointer-events-none z-[100] overflow-hidden hud-shell">

    <!-- ── Top-left: Smart Brush Panel ──────────────────────────── -->
    <div class="absolute top-7 left-7 animate-slide-left space-y-3">
      
      <!-- Main Brush Card -->
      <div 
        class="glass-panel hud-card pointer-events-auto flex items-center gap-4 px-4 py-3 transition-all duration-500"
        :style="{ borderColor: `${accentColor}44`, boxShadow: `0 18px 64px -24px rgba(0,0,0,.92), 0 0 38px -24px ${accentColor}` }"
      >
        <!-- Pressure Ring + Brush Dot -->
        <div class="relative flex items-center justify-center w-[52px] h-[52px]">
          <!-- Outer Glow -->
          <div 
            class="absolute inset-0 rounded-full blur-md opacity-20 animate-pulse"
            :style="{ backgroundColor: hudData.isEraseMode ? '#94a3b8' : accentColor }"
          />
          
          <!-- SVG Pressure Ring -->
          <svg
            v-if="hudData.pressureEnabled && !hudData.isEraseMode"
            class="absolute inset-0 w-12 h-12 -rotate-90 scale-110"
            viewBox="0 0 36 36"
          >
            <circle
              cx="18" cy="18" r="16"
              fill="none"
              stroke="rgba(255,255,255,0.08)"
              stroke-width="2.5"
            />
            <circle
              cx="18" cy="18" r="16"
              fill="none"
              stroke-linecap="round"
              stroke-width="2.5"
              :stroke="accentColor"
              :stroke-dasharray="strokeRingDash"
              class="transition-all duration-200 ease-out"
            />
          </svg>

          <!-- Center Dot -->
          <div
            class="rounded-full transition-all duration-300 z-10"
            :style="{
              width:  (brushDotPx * 1.5) + 'px',
              height: (brushDotPx * 1.5) + 'px',
              backgroundColor: hudData.isEraseMode ? '#94a3b8' : hudData.currentColor,
              boxShadow: hudData.isEraseMode ? 'none' : `0 0 15px ${hudData.currentColor}66`,
            }"
          />
        </div>

        <!-- Info Labels -->
        <div class="flex flex-col min-w-[102px]">
          <div class="flex items-center gap-2">
            <span class="text-[13px] font-black uppercase tracking-[0.16em] text-white">
              {{ currentBrushName }}
            </span>
            <span 
              v-if="hudData.strokeCount > 0"
              class="text-[10px] font-mono px-1.5 py-0.5 rounded-md bg-white/10 border border-white/10 text-white/60"
            >
              {{ Math.round((hudData.strokeCount / hudData.maxStrokes) * 100) }}%
            </span>
          </div>
          <span class="text-[10px] font-bold text-white/45 tracking-[0.22em] mt-0.5 uppercase">
            {{ hudData.isEraseMode ? 'Precision Eraser' : 'Aerosol Spray' }}
          </span>
        </div>

        <!-- Divider -->
        <div class="h-9 w-px bg-white/10 mx-1" />

        <!-- Stroke Counter -->
        <div v-if="hudData.strokeCount > 0" class="flex flex-col items-end min-w-[60px]">
          <span class="text-[13px] font-black font-mono text-white/90 leading-none">
            {{ hudData.strokeCount }}
          </span>
          <span class="text-[8px] font-bold text-white/35 uppercase tracking-[0.12em] mt-1">
            Strokes
          </span>
        </div>
      </div>

      <!-- Settings Panel (Density) -->
      <div v-if="!hudData.isEraseMode" class="animate-slide-up delay-100">
        <div class="glass-panel hud-card pointer-events-auto w-[282px] p-4 space-y-3">
          <div class="flex justify-between items-center">
            <span class="hud-label">Paint Scatter</span>
            <span class="hud-value">
              {{ Math.round(hudData.density * 100) }}%
            </span>
          </div>
          <div class="relative flex items-center group">
            <input
              type="range"
              min="0"
              max="1.0"
              step="0.05"
              :value="hudData.density"
              @input="onDensityChange"
              class="custom-range w-full"
            />
          </div>
        </div>
      </div>

      <!-- Advanced Tools (Import/Export) -->
      <div
        v-if="!hudData.isEraseMode && hudData.importExportEnabled"
        class="animate-slide-up delay-200"
      >
        <div class="glass-panel hud-card pointer-events-auto w-[282px] p-2 flex gap-2">
          <input
            v-model="importExportCode"
            type="text"
            placeholder="ENTER CODE..."
            class="flex-1 bg-black/25 text-white text-[10px] font-mono px-3 py-2 rounded-lg border border-white/10 focus:border-white/30 focus:outline-none placeholder:text-white/20 transition-all"
          />
          <button
            @click="doImport"
            class="tool-btn bg-emerald-400/10 hover:bg-emerald-400/20 text-emerald-300"
          >
            <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12" />
            </svg>
          </button>
          <button
            @click="doExport"
            class="tool-btn bg-cyan-300/10 hover:bg-cyan-300/20 text-cyan-200"
          >
            <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
            </svg>
          </button>
        </div>
      </div>
    </div>

    <!-- ── Left: Pro Color Palette ────────────────────────────── -->
    <div
      v-if="!hudData.isEraseMode && !hudData.forcedColor"
      class="absolute left-1/2 bottom-7 -translate-x-1/2"
    >
      <div class="glass-panel pointer-events-auto flex items-center gap-3 p-2.5 rounded-2xl border-white/10 shadow-2xl">
        <div class="text-[8px] font-black uppercase tracking-[0.22em] text-white/40 px-1">Palette</div>
        
        <!-- Swatches -->
        <div class="flex gap-2.5">
          <button
            v-for="(color, idx) in displayPresets"
            :key="idx"
            @click="selectColor(color)"
            class="swatch-ring group"
            :class="{ 'active': hudData.currentColor === color }"
          >
            <div 
              class="w-6 h-6 rounded-full transition-transform duration-300 group-hover:scale-110"
              :style="{ backgroundColor: color, boxShadow: hudData.currentColor === color ? `0 0 15px ${color}88` : 'none' }"
            />
          </button>
        </div>

        <div class="h-5 w-px bg-white/10 mx-1" />

        <!-- Picker Toggle -->
        <button
          v-if="hudData.enableColorPicker"
          @click="showColorPicker = !showColorPicker"
          class="w-8 h-8 rounded-lg flex items-center justify-center transition-all duration-300 hover:rotate-90"
          :class="showColorPicker ? 'bg-white text-black shadow-lg' : 'bg-white/10 text-white/60 hover:bg-white/15 hover:text-white'"
        >
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="3">
            <path stroke-linecap="round" d="M12 4v16m8-8H4" />
          </svg>
        </button>
      </div>

      <!-- Floating Picker -->
      <div
        v-if="showColorPicker && hudData.enableColorPicker"
        class="absolute left-1/2 bottom-full -translate-x-1/2 mb-4 pointer-events-auto"
      >
        <div class="glass-panel hud-card p-4 flex items-center gap-4 shadow-2xl border-white/10">
          <div class="relative group">
            <input
              type="color"
              :value="hudData.currentColor"
              @input="(e) => selectColor((e.target as HTMLInputElement).value)"
              class="w-12 h-12 rounded-xl cursor-pointer bg-transparent border-none p-0 overflow-hidden"
            />
            <div class="absolute inset-0 rounded-xl border border-white/20 pointer-events-none group-hover:border-white/40 transition-colors" />
          </div>
          <div class="flex flex-col">
            <span class="text-[9px] text-white/30 font-black uppercase tracking-widest">Active Hex</span>
            <span class="text-xs text-white/80 font-mono font-bold">{{ hudData.currentColor.toUpperCase() }}</span>
          </div>
        </div>
      </div>
    </div>

    <!-- ── Right: Command Center ────────────────────────────────── -->
    <div class="absolute right-7 top-1/2 -translate-y-1/2">
      <div class="glass-panel command-panel pointer-events-none w-[190px] p-4 space-y-5">
        
        <!-- Header -->
        <div class="flex items-center gap-3 px-1 pb-1">
          <div class="w-1.5 h-1.5 rounded-full bg-emerald-300 animate-pulse shadow-[0_0_10px_rgba(110,231,183,.9)]" />
          <span class="text-[10px] font-black uppercase tracking-[0.24em] text-white/60">Commands</span>
        </div>

        <!-- Keybind Groups -->
        <div class="space-y-4">
          <div class="space-y-2">
            <!-- Focus -->
            <div class="flex items-center justify-between group transition-all cursor-pointer pointer-events-auto hover:translate-x-1" @click="fetchNui('releaseMouse')">
              <span class="command-label">Focus</span>
              <div class="keycap">
                <span>ALT</span>
              </div>
            </div>
            <!-- Mode Action -->
            <div class="flex items-center justify-between group transition-all">
              <span class="command-label">{{ hudData.isEraseMode ? 'Erase' : 'Spray' }}</span>
              <div class="keycap">
                <span>LMB</span>
              </div>
            </div>
            <!-- Secondary Mode -->
            <div v-if="!hudData.isEraseMode" class="flex items-center justify-between group transition-all">
              <span class="command-label">Eraser</span>
              <div class="keycap">
                <span>RMB</span>
              </div>
            </div>
          </div>

          <div class="h-px bg-white/10" />

          <div class="space-y-2">
            <!-- Size -->
            <div class="flex items-center justify-between group transition-all">
              <span class="command-label">Size</span>
              <div class="keycap">
                <span>SCRL</span>
              </div>
            </div>
            <!-- Shake -->
            <div v-if="hudData.keys.shake && !hudData.isEraseMode" class="flex items-center justify-between group transition-all">
              <span class="command-label">Shake</span>
              <div class="keycap">
                <span>G</span>
              </div>
            </div>
            <!-- Depth -->
            <div class="flex items-center justify-between group transition-all">
              <span class="command-label">Depth</span>
              <div class="keycap">
                <span>↑ / ↓</span>
              </div>
            </div>
          </div>

          <div class="h-px bg-white/10" />

          <div class="space-y-2">
            <!-- Undo -->
            <div :class="['flex items-center justify-between group transition-all', hudData.canUndo ? 'opacity-100' : 'opacity-20']">
              <span class="command-label">Undo</span>
              <div class="keycap">
                <span>Z</span>
              </div>
            </div>
            <!-- Redo -->
            <div :class="['flex items-center justify-between group transition-all', hudData.canRedo ? 'opacity-100' : 'opacity-20']">
              <span class="command-label">Redo</span>
              <div class="keycap">
                <span>Y</span>
              </div>
            </div>
          </div>

          <div class="pt-2 flex gap-2">
            <button @click="fetchNui('confirmSpray')" class="action-btn save-btn flex-1">
              SAVE
            </button>
            <button @click="fetchNui('cancelSpray')" class="action-btn cancel-btn w-12">
              ×
            </button>
          </div>
        </div>
      </div>
    </div>

  </div>
</template>

<style scoped>
.hud-shell {
  background:
    linear-gradient(90deg, rgba(0, 0, 0, 0.26), transparent 18%, transparent 82%, rgba(0, 0, 0, 0.24)),
    radial-gradient(circle at 0% 14%, rgba(255, 255, 255, 0.055), transparent 25%),
    radial-gradient(circle at 100% 50%, rgba(16, 185, 129, 0.065), transparent 23%);
}

.hud-card,
.command-panel {
  border-radius: 18px;
}

.hud-label {
  @apply text-[10px] font-black uppercase tracking-[0.2em] text-white/50;
}

.hud-value {
  @apply rounded-md border border-emerald-300/15 bg-emerald-300/10 px-2 py-0.5 text-[10px] font-black font-mono text-emerald-200;
}

.command-label {
  @apply text-[10px] font-bold text-white/40 uppercase tracking-[0.18em] group-hover:text-white/70 transition-colors;
}

.keycap {
  @apply flex items-center justify-center min-w-[36px] h-[20px] px-2 rounded-md bg-white/10 border border-white/10 shadow-inner;
}

.keycap span {
  @apply text-[9px] font-black text-white/70 font-mono leading-none;
}

.custom-range {
  -webkit-appearance: none;
  width: 100%;
  height: 6px;
  background: linear-gradient(90deg, rgba(110, 231, 183, 0.36), rgba(255, 255, 255, 0.09));
  border-radius: 10px;
  outline: none;
  transition: all 0.3s;
  box-shadow: inset 0 1px 2px rgba(0, 0, 0, 0.5);
}

.custom-range::-webkit-slider-thumb {
  -webkit-appearance: none;
  width: 16px;
  height: 16px;
  background: #f8fff9;
  border: 2px solid rgba(16, 185, 129, 0.9);
  border-radius: 50%;
  cursor: pointer;
  box-shadow: 0 0 0 4px rgba(16, 185, 129, 0.12), 0 8px 18px rgba(0, 0, 0, 0.45);
  transition: all 0.2s;
}

.custom-range:hover::-webkit-slider-thumb {
  transform: scale(1.2);
  box-shadow: 0 0 20px rgba(255, 255, 255, 0.6);
}

.tool-btn {
  @apply w-10 h-10 rounded-lg flex items-center justify-center transition-all duration-300 hover:scale-105 active:scale-95 border border-white/10;
}

.swatch-ring {
  @apply relative p-1 rounded-full border border-transparent transition-all duration-300;
}

.swatch-ring.active {
  @apply border-white/60 scale-110 shadow-lg bg-white/10;
}

.action-btn {
  @apply h-10 rounded-xl text-[10px] font-black uppercase tracking-[0.2em] transition-all duration-300 border hover:scale-[1.02] active:scale-[0.98] pointer-events-auto;
}

.save-btn {
  @apply bg-emerald-300/15 text-emerald-100 border-emerald-300/25 hover:bg-emerald-300/25;
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.12), 0 10px 30px -18px rgba(110, 231, 183, 0.9);
}

.cancel-btn {
  @apply bg-white/10 text-white/60 border-white/10 hover:bg-white/15 hover:text-white/80;
}

/* Custom easing for animations */
.delay-100 { animation-delay: 0.1s; }
.delay-200 { animation-delay: 0.2s; }
.delay-300 { animation-delay: 0.3s; }
.delay-400 { animation-delay: 0.4s; }
</style>
