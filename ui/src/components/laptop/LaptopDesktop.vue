<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { fetchNui } from '@/utils/fetchNui'
import GangApp from './apps/GangApp.vue'
import MapApp from './apps/MapApp.vue'

const props = defineProps<{
  gang: any
  phone: string
}>()

const emit = defineEmits<{
  close: []
  gangUpdated: [gang: any]
}>()

type LaptopApp = 'home' | 'gang' | 'map' | 'market'

const activeApp = ref<LaptopApp>('gang')
const now = ref(new Date())
const minimized = ref(false)
const windowPos = ref({ x: 0, y: 0 })
const dragging = ref(false)
let dragOffset = { x: 0, y: 0 }
let timer = 0

const clock = computed(() => now.value.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }))
const title = computed(() => ({
  home: 'Workspace',
  gang: 'Gang Console',
  map: 'Territory Map',
  market: 'Black Market',
}[activeApp.value]))

const apps: Array<{ id: LaptopApp, label: string, icon: string, accent: string }> = [
  { id: 'home', label: 'Workspace', icon: 'H', accent: 'cyan' },
  { id: 'gang', label: 'Gang', icon: 'G', accent: 'red' },
  { id: 'map', label: 'Turf', icon: 'T', accent: 'green' },
  { id: 'market', label: 'Market', icon: '$', accent: 'amber' },
]

function centerWindow() {
  const width = Math.min(window.innerWidth * 0.78, 1180)
  const height = Math.min(window.innerHeight * 0.76, 720)
  windowPos.value = {
    x: Math.max(12, (window.innerWidth - width) / 2),
    y: Math.max(24, (window.innerHeight - height) / 2),
  }
}

function startDrag(event: MouseEvent) {
  if (minimized.value) return
  dragging.value = true
  dragOffset = {
    x: event.clientX - windowPos.value.x,
    y: event.clientY - windowPos.value.y,
  }
  window.addEventListener('mousemove', moveWindow)
  window.addEventListener('mouseup', stopDrag)
}

function moveWindow(event: MouseEvent) {
  if (!dragging.value) return
  const width = Math.min(window.innerWidth * 0.78, 1180)
  const height = Math.min(window.innerHeight * 0.76, 720)
  windowPos.value = {
    x: Math.max(8, Math.min(window.innerWidth - width - 8, event.clientX - dragOffset.x)),
    y: Math.max(8, Math.min(window.innerHeight - height - 8, event.clientY - dragOffset.y)),
  }
}

function stopDrag() {
  dragging.value = false
  window.removeEventListener('mousemove', moveWindow)
  window.removeEventListener('mouseup', stopDrag)
}

function closeLaptop() {
  fetchNui('laptop:close')
  emit('close')
}

function setApp(app: LaptopApp) {
  activeApp.value = app
  minimized.value = false
}

onMounted(() => {
  centerWindow()
  timer = window.setInterval(() => { now.value = new Date() }, 10000)
  window.addEventListener('resize', centerWindow)
})

onUnmounted(() => {
  window.clearInterval(timer)
  window.removeEventListener('resize', centerWindow)
  stopDrag()
})
</script>

<template>
  <div class="laptop-shell">
    <section
      class="laptop-frame"
      :class="{ minimized }"
      :style="{ transform: `translate(${windowPos.x}px, ${windowPos.y}px)` }"
    >
      <header class="laptop-topbar" @mousedown="startDrag">
        <div class="traffic">
          <button class="traffic-close" @click.stop="closeLaptop" aria-label="Close laptop" />
          <button class="traffic-min" @click.stop="minimized = !minimized" aria-label="Minimize laptop" />
          <button class="traffic-max" @click.stop="centerWindow" aria-label="Center laptop" />
        </div>
        <div class="topbar-title">
          <strong>PeakBook</strong>
          <span>{{ title }}</span>
        </div>
        <div class="topbar-status">
          <span>{{ phone }}</span>
          <span>VPN</span>
          <strong>{{ clock }}</strong>
        </div>
      </header>

      <div v-if="!minimized" class="laptop-body">
        <nav class="app-rail" aria-label="Laptop apps">
          <button
            v-for="app in apps"
            :key="app.id"
            :class="['rail-app', app.accent, { active: activeApp === app.id }]"
            :title="app.label"
            @click="setApp(app.id)"
          >
            <span>{{ app.icon }}</span>
          </button>
        </nav>

        <main class="laptop-workspace">
          <div v-if="activeApp === 'home'" class="workspace-home">
            <p class="eyebrow">Gang Workspace</p>
            <h2>{{ gang ? gang.name : 'No active gang' }}</h2>
            <p>{{ gang ? 'Review turf, members, alerts, and official marks from one console.' : 'Create or join a gang to unlock shared spray tools.' }}</p>
            <div class="home-actions">
              <button @click="setApp('gang')">Open Gang Console</button>
              <button @click="setApp('map')">Open Territory Map</button>
            </div>
          </div>

          <GangApp
            v-else-if="activeApp === 'gang'"
            :gang="props.gang"
            @updated="emit('gangUpdated', $event)"
            @open-map="setApp('map')"
          />
          <MapApp v-else-if="activeApp === 'map'" />

          <div v-else class="market-pane">
            <p class="eyebrow">Black Market</p>
            <h2>Spray Supply</h2>
            <div class="market-grid">
              <article><strong>Tier 1</strong><span>Basic spray work and turf upkeep.</span></article>
              <article><strong>Tier 2</strong><span>Priority alerts and contested-zone intel.</span></article>
              <article><strong>Tier 3</strong><span>Territory analytics for high-rep gangs.</span></article>
            </div>
          </div>
        </main>
      </div>
    </section>
  </div>
</template>
