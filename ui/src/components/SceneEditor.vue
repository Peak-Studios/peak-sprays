<script setup lang="ts">
import { computed } from 'vue'
import { fetchNui } from '@/utils/fetchNui'
import {
  BACKGROUNDS,
  FONTS,
  sceneState,
  setSceneData,
  setSceneField,
  type BackgroundFill,
  type FontOutline,
  type FontStyle,
  type RotationType,
  type SceneData,
  type Visibility,
} from '@/store/sceneState'

const currentBackground = computed(() => BACKGROUNDS.find(bg => bg.name === sceneState.sceneData.background))
const title = computed(() => sceneState.sceneType === 'sign' ? 'Sign' : 'Text Scene')
const quickPresets = computed(() => [
  ...sceneState.presets.slice(0, 2),
  ...sceneState.history.slice(0, 2),
])

function update<K extends keyof SceneData>(field: K, value: SceneData[K]) {
  setSceneField(field, value)
}

async function saveScene() {
  if (sceneState.saving) return
  sceneState.saving = true
  sceneState.error = ''
  try {
    const response = await fetchNui('sceneEditor:saveScene')
    if (!response?.success) sceneState.error = response?.error || 'Unable to save scene'
  } finally {
    sceneState.saving = false
  }
}

function selectPreset(data: SceneData) {
  const next = { ...data, text: data.text || sceneState.sceneData.text }
  delete next.createdAt
  setSceneData(next)
  void fetchNui('sceneEditor:sceneData', sceneState.sceneData)
}
</script>

<template>
  <div v-if="sceneState.visible" class="scene-editor-shell" :style="{ '--scene-accent': sceneState.accentColor }">
    <main class="scene-editor-panel">
      <header>
        <div>
          <p>{{ title }}</p>
          <h1>Scene Content</h1>
        </div>
        <div class="header-actions">
          <button class="header-save" type="button" :disabled="sceneState.saving" @click="saveScene">
            {{ sceneState.saving ? '...' : 'SAVE' }}
          </button>
          <button class="icon-button" type="button" aria-label="Close editor" @click="fetchNui('sceneEditor:close')">x</button>
        </div>
      </header>

      <div v-if="quickPresets.length" class="preset-strip">
        <button v-for="item in quickPresets" :key="`${item.text}-${item.createdAt || (item as any).name}`" type="button" @click="selectPreset(item)">
          {{ (item as any).name || item.text || 'Preset' }}
        </button>
      </div>

      <div class="scene-form">
        <label class="form-control">
          <span>Scene Content</span>
          <textarea
            :value="sceneState.sceneData.text"
            maxlength="200"
            rows="2"
            spellcheck="false"
            @input="update('text', ($event.target as HTMLTextAreaElement).value)"
          />
        </label>

        <label class="form-control">
          <span>Font</span>
          <select :value="sceneState.sceneData.font" @change="update('font', ($event.target as HTMLSelectElement).value)">
            <option v-for="font in FONTS" :key="font" :value="font">{{ font }}</option>
          </select>
        </label>

        <label class="form-control">
          <span>Font Size (Max 128)</span>
          <input type="number" min="12" max="128" :value="sceneState.sceneData.fontSize" @input="update('fontSize', Number(($event.target as HTMLInputElement).value))" />
        </label>

        <label class="form-control">
          <span>Font Color</span>
          <div class="color-row">
            <input type="color" :value="sceneState.sceneData.fontColor" @input="update('fontColor', ($event.target as HTMLInputElement).value)" />
            <strong>{{ sceneState.sceneData.fontColor.toUpperCase() }}</strong>
          </div>
        </label>

        <label class="form-control">
          <span>Font Outline</span>
          <select :value="sceneState.sceneData.fontOutline" @change="update('fontOutline', ($event.target as HTMLSelectElement).value as FontOutline)">
            <option value="none">No outline</option>
            <option value="shadow">Shadow</option>
            <option value="outline">Outline</option>
          </select>
        </label>

        <label v-if="sceneState.sceneData.fontOutline !== 'none'" class="form-control">
          <span>Outline Color</span>
          <div class="color-row">
            <input type="color" :value="sceneState.sceneData.fontOutlineColor" @input="update('fontOutlineColor', ($event.target as HTMLInputElement).value)" />
            <strong>{{ sceneState.sceneData.fontOutlineColor.toUpperCase() }}</strong>
          </div>
        </label>

        <label class="form-control">
          <span>Font Style</span>
          <select :value="sceneState.sceneData.fontStyle" @change="update('fontStyle', ($event.target as HTMLSelectElement).value as FontStyle)">
            <option value="normal">Normal</option>
            <option value="bold">Bold</option>
            <option value="italic">Italic</option>
          </select>
        </label>

        <label class="form-control">
          <span>Background</span>
          <select :value="sceneState.sceneData.background" @change="update('background', ($event.target as HTMLSelectElement).value)">
            <option v-for="bg in BACKGROUNDS" :key="bg.name" :value="bg.name">{{ bg.label }}</option>
          </select>
        </label>

        <label v-if="currentBackground?.hasColors" class="form-control">
          <span>Background Color</span>
          <div class="color-row">
            <input type="color" :value="sceneState.sceneData.backgroundColor" @input="update('backgroundColor', ($event.target as HTMLInputElement).value)" />
            <strong>{{ sceneState.sceneData.backgroundColor.toUpperCase() }}</strong>
          </div>
        </label>

        <label class="form-control">
          <span>Fill</span>
          <select :value="sceneState.sceneData.backgroundFill" @change="update('backgroundFill', ($event.target as HTMLSelectElement).value as BackgroundFill)">
            <option value="contain">Contain</option>
            <option value="cover">Cover</option>
          </select>
        </label>

        <label class="form-control">
          <span>Display Distance: {{ sceneState.sceneData.distance }}m</span>
          <input type="range" min="2" max="50" :value="sceneState.sceneData.distance" @input="update('distance', Number(($event.target as HTMLInputElement).value))" />
        </label>

        <label class="form-control">
          <span>Lifetime Hours</span>
          <input type="number" min="0" max="720" :value="sceneState.sceneData.hoursVisible" @input="update('hoursVisible', Number(($event.target as HTMLInputElement).value))" />
        </label>

        <label class="form-control">
          <span>Visibility</span>
          <select :value="sceneState.sceneData.visibility" @change="update('visibility', ($event.target as HTMLSelectElement).value as Visibility)">
            <option value="always">Always</option>
            <option value="close">Close</option>
            <option value="interaction_visible">Interaction Visible</option>
            <option value="interaction">Interaction Hidden</option>
          </select>
        </label>

        <label v-if="sceneState.sceneData.visibility === 'close'" class="form-control">
          <span>Close Distance: {{ sceneState.sceneData.closeDistance }}m</span>
          <input type="range" min="1" :max="sceneState.sceneData.distance" :value="sceneState.sceneData.closeDistance" @input="update('closeDistance', Number(($event.target as HTMLInputElement).value))" />
        </label>

        <label class="form-control">
          <span>Rotation</span>
          <select :value="sceneState.sceneData.rotationType" @change="update('rotationType', ($event.target as HTMLSelectElement).value as RotationType)">
            <option value="rotateGround">Align Surface</option>
            <option value="rotateTorwards">Face Camera</option>
            <option value="rotateKeep">Keep Heading</option>
          </select>
        </label>
      </div>

      <footer>
        <button class="position" type="button" @click="fetchNui('sceneEditor:editPosition')">Edit Position</button>
        <button class="save" type="button" :disabled="sceneState.saving" @click="saveScene">{{ sceneState.saving ? 'Saving...' : 'SAVE' }}</button>
      </footer>

      <p v-if="sceneState.error" class="scene-error">{{ sceneState.error }}</p>
    </main>
  </div>
</template>

<style scoped>
.scene-editor-shell {
  position: fixed;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: flex-end;
  padding: 24px 38px;
  pointer-events: none;
  background: transparent;
}

.scene-editor-panel {
  width: min(322px, calc(100vw - 32px));
  max-height: calc(100vh - 48px);
  padding: 14px;
  pointer-events: auto;
  border: 1px solid rgba(255, 255, 255, .12);
  border-radius: 16px;
  background:
    linear-gradient(180deg, rgba(39, 45, 43, .68), rgba(11, 17, 12, .58)),
    rgba(8, 12, 10, .34);
  box-shadow: inset 0 1px 0 rgba(255,255,255,.12), 0 22px 70px -30px rgba(0,0,0,.88);
  overflow: hidden;
}

header,
footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

header p {
  color: var(--scene-accent);
  font-size: 10px;
  font-weight: 900;
  text-transform: uppercase;
  letter-spacing: .18em;
  margin: 0 0 2px;
}

header h1 {
  margin: 0;
  color: rgba(255,255,255,.94);
  font-size: 14px;
  font-weight: 900;
  text-transform: uppercase;
  letter-spacing: .08em;
}

.header-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

.header-save {
  height: 30px;
  min-height: 0;
  padding: 0 12px;
  font-size: 10px;
  font-weight: 900;
  letter-spacing: 0.1em;
  border-radius: 8px;
  border-color: color-mix(in srgb, var(--scene-accent), transparent 40%);
  background: color-mix(in srgb, var(--scene-accent), transparent 85%);
  color: color-mix(in srgb, white, var(--scene-accent) 10%);
  transition: all 0.2s;
}

.header-save:hover:not(:disabled) {
  background: color-mix(in srgb, var(--scene-accent), transparent 70%);
  transform: translateY(-1px);
}

.header-save:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.icon-button {
  width: 30px;
  min-height: 30px;
  padding: 0;
  border-radius: 8px;
  color: rgba(255,255,255,.72);
}

.preset-strip {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 7px;
  margin: 12px 0 8px;
}

.preset-strip button {
  min-height: 30px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: rgba(255,255,255,.68);
  font-size: 9px;
  text-transform: uppercase;
  letter-spacing: .07em;
}

.scene-form {
  display: flex;
  flex-direction: column;
  gap: 9px;
  margin: 14px -4px 14px 0;
  max-height: calc(100vh - 190px);
  overflow: auto;
  padding: 0 6px 2px 0;
}

.form-control {
  display: grid;
  gap: 6px;
}

.form-control span {
  color: rgba(255,255,255,.5);
  font-size: 10px;
  font-weight: 900;
  text-transform: uppercase;
  letter-spacing: .08em;
  text-shadow: 0 1px 2px rgba(0,0,0,.55);
}

input,
select,
textarea,
button {
  border-radius: 7px;
  font-family: inherit;
}

input,
select,
textarea {
  width: 100%;
  min-height: 39px;
  border: 1px solid rgba(135,218,33,.16);
  background: rgba(5, 22, 2, .88);
  color: rgba(255,255,255,.94);
  padding: 9px 12px;
  outline: none;
  box-shadow: inset 0 1px 0 rgba(255,255,255,.05), 0 10px 24px -20px rgba(0,0,0,.9);
}

textarea {
  resize: none;
  min-height: 44px;
  font-weight: 800;
  text-transform: uppercase;
}

button {
  min-height: 38px;
  border: 1px solid rgba(255,255,255,.14);
  background: rgba(255,255,255,.09);
  color: white;
  padding: 0 14px;
  font-size: 11px;
  font-weight: 900;
}

.color-row {
  display: grid;
  grid-template-columns: 38px 1fr;
  align-items: center;
  gap: 10px;
  min-height: 39px;
  border: 1px solid rgba(135,218,33,.16);
  border-radius: 7px;
  background: rgba(5, 22, 2, .88);
  padding: 6px 10px;
}

.color-row input {
  width: 25px;
  height: 25px;
  min-height: 0;
  padding: 0;
  border: 0;
  background: transparent;
  box-shadow: none;
}

.color-row strong {
  color: rgba(255,255,255,.88);
  font-size: 12px;
  font-weight: 900;
}

input[type="range"] {
  min-height: 30px;
  padding: 0;
  accent-color: var(--scene-accent);
  background: transparent;
  box-shadow: none;
}

footer {
  padding-top: 6px;
}

footer button {
  min-width: 88px;
}

button.position {
  color: rgba(255,255,255,.78);
  background: rgba(255,255,255,.12);
}

button.save {
  border-color: color-mix(in srgb, var(--scene-accent), transparent 22%);
  background: color-mix(in srgb, var(--scene-accent), transparent 78%);
  color: color-mix(in srgb, white, var(--scene-accent) 18%);
}

.scene-error {
  color: #fca5a5;
  font-size: 13px;
}
</style>
