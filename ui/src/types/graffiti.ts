export type LayerType = 'freehand' | 'text' | 'image' | 'stencil'

export type BrushStyleId =
  | 'spray'
  | 'rough_spray'
  | 'chalk'
  | 'crayon'
  | 'marker_bleed'
  | 'stipple'
  | 'roller'
  | 'scratched'
  | 'pen'
  | 'calligraphy'
  | 'splatter'
  | 'airbrush'
  | 'drip'

export interface StrokePoint {
  x: number
  y: number
  pressure?: number
  t?: number
}

export interface FreehandStroke {
  type: 'paint' | 'erase' | 'stencil'
  style?: BrushStyleId | string
  color: string
  size: number
  density?: number
  pressure?: number
  scatter?: number
  points: StrokePoint[]
}

export interface WorldEraseStroke {
  type: 'erase' | 'world_clean'
  size: number
  points: StrokePoint[]
}

export interface TextOutline {
  enabled: boolean
  color: string
  width: number
}

export interface TextShadow {
  enabled: boolean
  color: string
  blur: number
  offsetX: number
  offsetY: number
}

export interface TextGlow {
  enabled: boolean
  color: string
  blur: number
}

export interface TextDripEffect {
  enabled: boolean
  count: number
  length: number
  width: number
}

export interface TextSprayEffect {
  enabled: boolean
  count: number
  spread: number
}

export interface TextDistressEffect {
  enabled: boolean
  roughness: number // 0 to 1
}

export interface ImageFilters {
  brightness: number // -100 to 100
  contrast: number   // -100 to 100
  monochrome: boolean
  blur: number       // 0 to 20
  removeBg: boolean
  removeBgThreshold: number // 0 to 100
}

export interface BaseLayer {
  id: string
  name: string
  type: LayerType
  visible: boolean
  locked: boolean
  opacity: number
}

export interface FreehandLayer extends BaseLayer {
  type: 'freehand'
  strokes: FreehandStroke[]
  brushStyle?: BrushStyleId
}

export interface TextLayer extends BaseLayer {
  type: 'text'
  text: string
  font: string
  fontSize: number
  fontWeight: 'normal' | 'bold' | '900'
  fontStyle: 'normal' | 'italic'
  letterSpacing: number
  lineHeight: number
  color: string
  x: number
  y: number
  rotation: number
  scale: number
  outline: TextOutline
  shadow: TextShadow
  glow: TextGlow
  drip: TextDripEffect
  spray: TextSprayEffect
  distress: TextDistressEffect
}

export interface ImageLayer extends BaseLayer {
  type: 'image'
  url: string
  dataUrl?: string
  x: number
  y: number
  width: number
  height: number
  rotation: number
  flipX: boolean
  flipY: boolean
  filters: ImageFilters
}

export interface StencilLayer extends BaseLayer {
  type: 'stencil'
  stencilId: string
  x: number
  y: number
  size: number
  rotation: number
  color: string
}

export type GraffitiLayer = FreehandLayer | TextLayer | ImageLayer | StencilLayer

/** Pure editable drawing composition document */
export interface GraffitiComposition {
  version: string
  title: string
  width: number
  height: number
  background: 'transparent' | 'brick' | 'concrete' | 'metal' | 'wood' | 'tile' | string
  layers: GraffitiLayer[]
  eraseMask?: WorldEraseStroke[]
}

export interface StencilPreset {
  name: string
  points: { x: number; y: number }[]
}

/** Library persistence record containing metadata plus nested composition */
export interface DesignRecord {
  id: number
  identifier?: string
  playerName: string
  title: string
  category: 'draft' | 'saved' | 'template' | 'gang'
  gangId?: string | null
  variant?: string
  isServerTemplate: boolean
  thumbnail?: string | null
  layerCount: number
  createdAt?: string
  updatedAt?: string
  composition: GraffitiComposition
}

/** Lightweight summary for library grid listings */
export interface DesignSummary {
  id: number
  identifier?: string
  playerName: string
  title: string
  category: 'draft' | 'saved' | 'template' | 'gang'
  gangId?: string | null
  variant?: string
  isServerTemplate: boolean
  thumbnail?: string | null
  layerCount: number
  createdAt?: string
  updatedAt?: string
}

export interface PlayerGangInfo {
  id: string
  name: string
  label: string
  isBoss: boolean
  grade: number
}

export interface DesignLibrary {
  drafts: DesignRecord[]
  saved: DesignRecord[]
  recent: DesignRecord[]
  templates: DesignRecord[]
  gang: DesignRecord[]
  playerGang?: PlayerGangInfo
  playerIdentifier?: string
}

/** Server Request / Response Contracts */
export interface SaveDesignRequest {
  id?: number | null
  title: string
  category?: 'draft' | 'saved' | 'template' | 'gang'
  variant?: string
  composition: GraffitiComposition
  thumbnail?: string | null
}

export interface SaveDesignResponse {
  success: boolean
  id?: number
  message?: string
}

export interface DeleteDesignRequest {
  id: number
}

export interface DeleteDesignResponse {
  success: boolean
  message?: string
}

export interface PublishGangTemplateRequest {
  title: string
  variant?: string
  composition: GraffitiComposition
  thumbnail?: string | null
}

export interface PublishGangTemplateResponse {
  success: boolean
  id?: number
  message?: string
}

export interface ExportDesignResponse {
  success: boolean
  json?: string
  message?: string
}

export interface ImportDesignResponse {
  success: boolean
  id?: number
  message?: string
}
