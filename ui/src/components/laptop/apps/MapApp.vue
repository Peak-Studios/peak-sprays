<script setup lang="ts">
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import { fetchNui } from '@/utils/fetchNui'

type TerritorySpray = {
  id: number
  gang_id: number
  gangId: number
  gangName: string
  gangColor: string
  status: string
  world_x: number
  world_y: number
  world_z: number
  radius: number
  contestedRadius: number
  placementRadius: number
  created_at?: string
  discovered?: boolean
  isOwnGang?: boolean
}

const sprays = ref<TerritorySpray[]>([])
const summary = ref<any>(null)
const loading = ref(true)
const selected = ref<TerritorySpray | null>(null)
const gangFilter = ref('all')
const statusFilter = ref('all')

let map: L.Map | null = null
let territoryLayer: L.LayerGroup | null = null

const CenterX = 117.3
const CenterY = 172.8
const ScaleX = 0.02072
const ScaleY = 0.0205

const customCrs = L.extend({}, L.CRS.Simple, {
  projection: L.Projection.LonLat,
  transformation: new L.Transformation(ScaleX, CenterX, -ScaleY, CenterY),
  scale(zoom: number) {
    return Math.pow(2, zoom)
  },
  zoom(scale: number) {
    return Math.log(scale) / Math.LN2
  },
  distance(pos1: L.LatLng, pos2: L.LatLng) {
    const x = pos2.lng - pos1.lng
    const y = pos2.lat - pos1.lat
    return Math.sqrt((x * x) + (y * y))
  },
  infinite: true,
})

const gangOptions = computed(() => {
  const map = new Map<number, { id: number, name: string, color: string, total: number }>()
  for (const spray of sprays.value) {
    const id = Number(spray.gangId || spray.gang_id)
    const current = map.get(id) || { id, name: spray.gangName, color: spray.gangColor, total: 0 }
    current.total += 1
    map.set(id, current)
  }
  return Array.from(map.values()).sort((a, b) => a.name.localeCompare(b.name))
})

const filteredSprays = computed(() => sprays.value.filter((spray) => {
  const gangOk = gangFilter.value === 'all' || Number(gangFilter.value) === Number(spray.gangId || spray.gang_id)
  const statusOk = statusFilter.value === 'all' || spray.status === statusFilter.value
  return gangOk && statusOk
}))

function normalizePayload(result: any) {
  if (Array.isArray(result)) return result
  if (Array.isArray(result?.data)) return result.data
  return []
}

function markerPopup(spray: TerritorySpray) {
  const wrapper = document.createElement('div')
  const title = document.createElement('strong')
  const status = document.createElement('span')
  const button = document.createElement('button')

  wrapper.className = 'territory-popup'
  title.textContent = spray.gangName
  status.textContent = spray.status === 'contested' ? 'Contested turf' : 'Owned turf'
  button.type = 'button'
  button.textContent = 'Inspect'
  button.addEventListener('click', () => {
    selected.value = spray
  })
  wrapper.append(title, status, button)
  return wrapper
}

function redrawMap() {
  if (!map || !territoryLayer) return
  territoryLayer.clearLayers()

  for (const spray of filteredSprays.value) {
    const latLng: L.LatLngExpression = [Number(spray.world_y), Number(spray.world_x)]
    const isContested = spray.status === 'contested'
    const color = isContested ? '#ef4444' : (spray.gangColor || '#22c55e')
    const radius = isContested ? Number(spray.contestedRadius || 50) : Number(spray.radius || 90)

    L.circle(latLng, {
      radius,
      color,
      weight: isContested ? 2 : 1.25,
      opacity: isContested ? 0.95 : 0.75,
      fillColor: color,
      fillOpacity: isContested ? 0.22 : 0.16,
      className: isContested ? 'leaflet-contested-zone' : 'leaflet-owned-zone',
    }).addTo(territoryLayer)

    const marker = L.circleMarker(latLng, {
      radius: isContested ? 7 : 5,
      fillColor: color,
      color: '#f8fafc',
      weight: 1.5,
      opacity: 1,
      fillOpacity: 0.95,
      className: isContested ? 'territory-marker contested' : 'territory-marker',
    })

    marker.on('click', () => { selected.value = spray })
    marker.bindPopup(markerPopup(spray), { closeButton: false, className: 'territory-leaflet-popup' })
    marker.addTo(territoryLayer)
  }
}

async function loadMap() {
  loading.value = true
  const [mapRows, mapSummary] = await Promise.all([
    fetchNui('territory:getMap'),
    fetchNui('territory:getSummary'),
  ])
  sprays.value = normalizePayload(mapRows)
  summary.value = mapSummary?.data || mapSummary || null
  selected.value = sprays.value.find((spray) => spray.status === 'contested') || sprays.value[0] || null
  loading.value = false
  await nextTick()
  redrawMap()
}

onMounted(async () => {
  await nextTick()
  map = L.map('territory-leaflet-map', {
    crs: customCrs,
    minZoom: 2,
    maxZoom: 6,
    center: [0, 0],
    zoom: 3,
    preferCanvas: true,
    attributionControl: false,
    zoomControl: true,
    keyboard: false,
  })

  const width = 1024
  const height = 1024
  const southWest = map.unproject([0, height], 2)
  const northEast = map.unproject([width, 0], 2)
  const bounds = new L.LatLngBounds(southWest, northEast)

  L.imageOverlay('./images/territory_map.png', bounds).addTo(map)
  map.setMaxBounds(bounds)
  territoryLayer = L.layerGroup().addTo(map)
  await loadMap()
  window.setTimeout(() => map?.invalidateSize(), 60)
})

onUnmounted(() => {
  map?.remove()
  map = null
  territoryLayer = null
})

watch([filteredSprays, gangFilter, statusFilter], redrawMap)
</script>

<template>
  <div class="map-app">
    <header class="map-header">
      <div>
        <p class="eyebrow">Territory Map</p>
        <h2>{{ summary?.total || sprays.length }} turf zones</h2>
      </div>
      <button @click="loadMap">{{ loading ? 'Loading' : 'Refresh' }}</button>
    </header>

    <div class="map-toolbar">
      <label>
        <span>Gang</span>
        <select v-model="gangFilter">
          <option value="all">All gangs</option>
          <option v-for="gang in gangOptions" :key="gang.id" :value="gang.id">
            {{ gang.name }} ({{ gang.total }})
          </option>
        </select>
      </label>
      <label>
        <span>Status</span>
        <select v-model="statusFilter">
          <option value="all">All zones</option>
          <option value="normal">Owned</option>
          <option value="contested">Contested</option>
        </select>
      </label>
      <div class="map-stat"><span>Contested</span><strong>{{ summary?.contested || 0 }}</strong></div>
      <div class="map-stat"><span>Discovered</span><strong>{{ summary?.discovered || 0 }}</strong></div>
    </div>

    <div class="map-layout">
      <div class="territory-map-panel">
        <div id="territory-leaflet-map"></div>
        <span v-if="loading" class="map-empty">Loading territory</span>
        <span v-else-if="!filteredSprays.length" class="map-empty">No matching turf</span>
      </div>

      <aside class="territory-inspector">
        <template v-if="selected">
          <p class="eyebrow">Selected Turf</p>
          <h3>{{ selected.gangName }}</h3>
          <dl>
            <div><dt>Status</dt><dd>{{ selected.status }}</dd></div>
            <div><dt>Radius</dt><dd>{{ selected.status === 'contested' ? selected.contestedRadius : selected.radius }}m</dd></div>
            <div><dt>Placement Gap</dt><dd>{{ selected.placementRadius }}m</dd></div>
            <div><dt>Coords</dt><dd>{{ Number(selected.world_x).toFixed(1) }}, {{ Number(selected.world_y).toFixed(1) }}</dd></div>
          </dl>
        </template>
        <p v-else class="status-line">Select a zone on the map.</p>
      </aside>
    </div>
  </div>
</template>
