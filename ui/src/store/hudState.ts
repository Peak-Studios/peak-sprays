import { reactive } from 'vue'

export interface BrushSize {
  name: string
  size: number
  sprayDensity: number
}

export interface KeyBinds {
  mouse?: string
  shake?: string
  size?: string
  paint?: string
  erase?: string
  validate?: string
  cancel?: string
  undo?: string
  redo?: string
  forward?: string
  backward?: string
}

export const hudData = reactive({
  brushSizes:          [] as BrushSize[],
  currentBrushIndex:   0,
  currentColor:        '#000000',
  forcedColor:         null as string | null,
  colorPresets:        [] as string[],
  enableColorPicker:   true,
  pressure:            0.8,
  density:             0.7,
  pressureEnabled:     true,
  keys:                {} as KeyBinds,
  isEraseMode:         false,
  strokeCount:         0,
  maxStrokes:          500,
  canUndo:             false,
  canRedo:             false,
  importExportEnabled: false,
  lastExportCode:      '',
  paintStyles:         [] as any[],
  currentStyleIndex:   1,
  stencils:            [] as any[],
  currentStencilIndex: 1,
})

export const showHUD = reactive({ value: false })
