import { reactive } from 'vue'
import { fetchNui } from '@/utils/fetchNui'

export type FontOutline = 'none' | 'shadow' | 'outline'
export type FontStyle = 'normal' | 'italic' | 'bold'
export type BackgroundFill = 'cover' | 'contain'
export type RotationType = 'rotateTorwards' | 'rotateKeep' | 'rotateGround'
export type Visibility = 'always' | 'interaction' | 'interaction_visible' | 'close'

export interface SceneData {
  text: string
  font: string
  fontSize: number
  fontColor: string
  fontOutline: FontOutline
  fontOutlineColor: string
  fontStyle: FontStyle
  background: string
  backgroundFill: BackgroundFill
  backgroundOffsetX: number
  backgroundOffsetY: number
  backgroundSizeX: number
  backgroundSizeY: number
  backgroundColor: string
  rotationType: RotationType
  distance: number
  closeDistance: number
  hoursVisible: number
  visibility: Visibility
  createdAt?: string | number
  sceneType?: string
}

export interface Option<T = string | number> {
  name: T
  label: string
  hasColors?: boolean
}

export const DEFAULT_SCENE: SceneData = {
  text: 'This is a scene.',
  font: 'Oswald',
  fontSize: 48,
  fontColor: '#ffffff',
  fontOutline: 'none',
  fontOutlineColor: '#000000',
  fontStyle: 'normal',
  background: 'empty',
  backgroundFill: 'contain',
  backgroundOffsetX: 50,
  backgroundOffsetY: 50,
  backgroundSizeX: 100,
  backgroundSizeY: 100,
  backgroundColor: '#262626',
  rotationType: 'rotateGround',
  distance: 10,
  closeDistance: 3,
  hoursVisible: 24,
  visibility: 'always',
}

export const FONTS = ['Geist', 'Oswald', 'Montserrat', 'Lato', 'Merriweather', 'Raleway', 'Lobster', 'Creepster', 'Rock Salt', 'Nosifer']

export const BACKGROUNDS: Option[] = [
  { name: 'empty', label: 'Empty' },
  { name: 'solid', label: 'Solid', hasColors: true },
  { name: 'sticky', label: 'Sticky' },
  { name: 'oldPaper', label: 'Old Paper' },
  { name: 'oldPaper2', label: 'Old Paper 2' },
  { name: 'oldPaper3', label: 'Old Paper 3' },
  { name: 'tornPaper', label: 'Torn Paper' },
  { name: 'warning', label: 'Warning' },
  { name: 'wood', label: 'Wood' },
  { name: 'water', label: 'Water' },
  { name: 'blood', label: 'Blood' },
  { name: 'blueprint', label: 'Blueprint' },
]

export const sceneState = reactive({
  visible: false,
  sceneType: 'scene',
  accentColor: '#87da21',
  sceneData: { ...DEFAULT_SCENE } as SceneData,
  history: [] as SceneData[],
  presets: [] as SceneData[],
  saving: false,
  error: '',
})

export function normalizeScene(data: Partial<SceneData>): SceneData {
  return {
    ...DEFAULT_SCENE,
    ...data,
    fontSize: Number(data.fontSize ?? DEFAULT_SCENE.fontSize),
    distance: Number(data.distance ?? DEFAULT_SCENE.distance),
    closeDistance: Number(data.closeDistance ?? DEFAULT_SCENE.closeDistance),
    hoursVisible: Number(data.hoursVisible ?? DEFAULT_SCENE.hoursVisible),
    backgroundOffsetX: Number(data.backgroundOffsetX ?? DEFAULT_SCENE.backgroundOffsetX),
    backgroundOffsetY: Number(data.backgroundOffsetY ?? DEFAULT_SCENE.backgroundOffsetY),
    backgroundSizeX: Number(data.backgroundSizeX ?? DEFAULT_SCENE.backgroundSizeX),
    backgroundSizeY: Number(data.backgroundSizeY ?? DEFAULT_SCENE.backgroundSizeY),
  }
}

export function setSceneData(data: Partial<SceneData>) {
  sceneState.sceneData = normalizeScene(data)
}

export function setSceneField<K extends keyof SceneData>(field: K, value: SceneData[K]) {
  ;(sceneState.sceneData[field] as SceneData[K]) = value
  void fetchNui('sceneEditor:sceneData', sceneState.sceneData)
}

export function dispatchSceneAction(app: string, action: string, payload: any) {
  if (app === 'root' && action === 'setConfig') {
    sceneState.accentColor = payload?.accentColor || sceneState.accentColor
    return
  }

  if (app !== 'sceneEditor') return

  if (action === 'setVisible') sceneState.visible = Boolean(payload)
  if (action === 'setSceneType') sceneState.sceneType = payload || 'scene'
  if (action === 'setHistory') sceneState.history = Array.isArray(payload) ? payload : []
  if (action === 'setPresets') sceneState.presets = Array.isArray(payload) ? payload : []
  if (action === 'setSceneData') setSceneData(payload || {})
  if (action === 'newScene') {
    const next = typeof payload === 'object' ? payload : { text: payload || DEFAULT_SCENE.text }
    setSceneData(next)
    void fetchNui('sceneEditor:sceneData', sceneState.sceneData)
  }
}
