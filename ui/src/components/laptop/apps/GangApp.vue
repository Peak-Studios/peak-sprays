<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { fetchNui } from '@/utils/fetchNui'

const props = defineProps<{ gang: any }>()
const emit = defineEmits<{ updated: [gang: any], openMap: [] }>()

type Tab = 'overview' | 'members' | 'turf' | 'mark' | 'activity'

const activeTab = ref<Tab>('overview')
const gangName = ref('')
const targetId = ref('')
const markName = ref('Official Mark')
const status = ref('')
const loading = ref(false)
const dashboard = ref<any>(null)

const gangData = computed(() => dashboard.value?.gang || props.gang)
const summary = computed(() => dashboard.value?.summary || {})
const permissions = computed(() => dashboard.value?.permissions || {})
const activity = computed(() => dashboard.value?.activity || gangData.value?.metadata?.activity || [])

const tabs: Array<{ id: Tab, label: string }> = [
  { id: 'overview', label: 'Overview' },
  { id: 'members', label: 'Members' },
  { id: 'turf', label: 'Turf' },
  { id: 'mark', label: 'Mark' },
  { id: 'activity', label: 'Activity' },
]

watch(() => props.gang, () => { status.value = '' })

async function loadDashboard() {
  loading.value = true
  const result = await fetchNui('gang:getDashboard')
  dashboard.value = result?.data || result
  loading.value = false
}

async function createGang() {
  const result = await fetchNui('gang:create', { name: gangName.value })
  if (result?.success) {
    emit('updated', result.gang)
    await loadDashboard()
  }
  status.value = result?.message || (result?.success ? 'Gang created.' : 'Unable to create gang.')
}

async function addMember() {
  const result = await fetchNui('gang:addMember', { targetId: Number(targetId.value) })
  if (result?.success) {
    emit('updated', result.gang)
    targetId.value = ''
    await loadDashboard()
  }
  status.value = result?.message || (result?.success ? 'Member added.' : 'Unable to add member.')
}

async function setRank(identifier: string, rank: string) {
  const result = await fetchNui('gang:setRank', { identifier, rank })
  if (result?.success) {
    emit('updated', result.gang)
    await loadDashboard()
  }
  status.value = result?.message || (result?.success ? 'Rank updated.' : 'Unable to update rank.')
}

async function kick(identifier: string) {
  const result = await fetchNui('gang:kick', { identifier })
  if (result?.success) {
    emit('updated', result.gang)
    await loadDashboard()
  }
  status.value = result?.message || (result?.success ? 'Member removed.' : 'Unable to remove member.')
}

async function saveMark() {
  const mark = {
    name: markName.value,
    strokes: [
      { type: 'paint', style: 'spray', color: '#0f172a', size: 18, density: 24, pressure: 0.9, scatter: 0.6, points: [{ x: 360, y: 500 }, { x: 520, y: 430 }, { x: 660, y: 500 }] },
      { type: 'paint', style: 'spray', color: '#ef4444', size: 14, density: 20, pressure: 0.85, scatter: 0.5, points: [{ x: 410, y: 560 }, { x: 610, y: 560 }] },
    ],
  }
  const result = await fetchNui('gang:setOfficialMark', { mark })
  if (result?.success) {
    emit('updated', result.gang)
    await loadDashboard()
  }
  status.value = result?.message || (result?.success ? 'Official mark saved.' : 'Unable to save mark.')
}

function formatTime(value: number) {
  if (!value) return 'Never'
  return new Date(value * 1000).toLocaleString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
}

onMounted(loadDashboard)
</script>

<template>
  <div class="gang-app">
    <div v-if="!gangData" class="create-gang">
      <p class="eyebrow">Unknown Access</p>
      <h2>Create Gang</h2>
      <div class="form-row">
        <input v-model="gangName" placeholder="Gang name" maxlength="80">
        <button @click="createGang">Create</button>
      </div>
      <p class="status-line">{{ status }}</p>
    </div>

    <template v-else>
      <header class="gang-command-header">
        <div>
          <p class="eyebrow">Gang Console</p>
          <h2>{{ gangData.name }}</h2>
          <span>{{ permissions.rank || 'member' }} access</span>
        </div>
        <button @click="loadDashboard">{{ loading ? 'Syncing' : 'Refresh' }}</button>
      </header>

      <nav class="gang-tabs" aria-label="Gang sections">
        <button
          v-for="tab in tabs"
          :key="tab.id"
          :class="{ active: activeTab === tab.id }"
          @click="activeTab = tab.id"
        >
          {{ tab.label }}
        </button>
      </nav>

      <section v-if="activeTab === 'overview'" class="gang-overview">
        <div class="metric-row">
          <article><span>Reputation</span><strong>{{ gangData.metadata?.xp || 0 }}</strong></article>
          <article><span>Tier</span><strong>{{ gangData.metadata?.tier || 1 }}</strong></article>
          <article><span>Active Sprays</span><strong>{{ summary.activeSprays || 0 }}</strong></article>
          <article><span>Contested</span><strong>{{ summary.contestedSprays || 0 }}</strong></article>
        </div>
        <div class="overview-grid">
          <div>
            <h3>Progression</h3>
            <p>{{ summary.onlineMembers || 0 }} online members. {{ summary.discoveredSprays || 0 }} discovered sprays tracked.</p>
          </div>
          <div>
            <h3>Last Spray</h3>
            <p>{{ formatTime(gangData.metadata?.lastSprayTimestamp) }}</p>
          </div>
          <div>
            <h3>Last Contest</h3>
            <p>{{ formatTime(gangData.metadata?.lastSprayContest) }}</p>
          </div>
        </div>
      </section>

      <section v-else-if="activeTab === 'members'" class="members-panel">
        <header>
          <h3>Roster</h3>
          <div class="form-row compact">
            <input v-model="targetId" placeholder="Server ID" :disabled="!permissions.canInvite">
            <button :disabled="!permissions.canInvite" @click="addMember">Invite</button>
          </div>
        </header>
        <div class="member-list">
          <article v-for="member in gangData.members" :key="member.identifier" class="member-row">
            <div>
              <strong>{{ member.name }}</strong>
              <span>{{ member.rank }}</span>
            </div>
            <div class="member-actions">
              <button :disabled="!permissions.canLead || member.rank === 'leader'" @click="setRank(member.identifier, member.rank === 'officer' ? 'member' : 'officer')">Rank</button>
              <button :disabled="!permissions.canManage || member.rank === 'leader'" @click="kick(member.identifier)">Kick</button>
            </div>
          </article>
        </div>
      </section>

      <section v-else-if="activeTab === 'turf'" class="turf-panel">
        <div class="turf-summary">
          <article><span>Owned zones</span><strong>{{ summary.activeSprays || 0 }}</strong></article>
          <article><span>Discovered</span><strong>{{ summary.discoveredSprays || 0 }}</strong></article>
          <article><span>Contested</span><strong>{{ summary.contestedSprays || 0 }}</strong></article>
        </div>
        <button class="wide-action" @click="emit('openMap')">Open Territory Map</button>
      </section>

      <section v-else-if="activeTab === 'mark'" class="mark-panel">
        <h3>Official Mark</h3>
        <div class="mark-preview">
          <div class="mark-canvas">
            <span></span>
            <i></i>
          </div>
        </div>
        <div class="form-row">
          <input v-model="markName" placeholder="Mark name">
          <button :disabled="!permissions.canManage" @click="saveMark">Promote</button>
        </div>
      </section>

      <section v-else class="activity-panel">
        <article v-for="item in activity" :key="`${item.time}-${item.title}`">
          <span>{{ formatTime(item.time) }}</span>
          <strong>{{ item.title }}</strong>
          <p>{{ item.message }}</p>
        </article>
        <p v-if="!activity.length" class="status-line">No gang activity yet.</p>
      </section>

      <p class="status-line">{{ status }}</p>
    </template>
  </div>
</template>
