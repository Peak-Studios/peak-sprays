Config = Config or {}

-- ============================================================
-- INTERNAL CONFIGURATION (ADVANCED)
-- This file contains technical defaults and performance settings.
-- Only modify these if you know what you are doing.
-- ============================================================

-- Core Technical Settings
Config.Debug = false
Config.AdminGroups = { 'group.admin', 'admin', 'god', 'superadmin' }
Config.AdminAce = 'admin'
Config.EnableVersionChecker = true
Config.VersionURL = 'https://raw.githubusercontent.com/Peak-Studios/peak-sprays/main/version.json'
Config.ShowChangelog = true

-- System Detection Defaults
Config.Banking = 'auto'
Config.DefaultMoneyType = 'cash'
Config.Notify = 'auto'
Config.Target = 'auto'
Config.Progress = 'auto'
Config.Inventory = 'auto'
Config.Ambulance = 'auto'
Config.SQLDriver = 'auto'

-- Item & Command Settings
Config.UseItem = true
Config.UseCommand = true
Config.EraseCommandName = 'erasepaint'
Config.AdminCommandName = 'sprayadmin'
Config.ConsumeSprayOnValidate = true
Config.ConsumeClothOnValidate = true
Config.SprayUsesPerItem = 1
Config.ClothUsesPerItem = 1
Config.ColoredItems = {}

-- DUI Canvas 
Config.CanvasWidth = 1024
Config.CanvasHeight = 1024

-- Paint Area
Config.MaxPaintAreaWidth = 5.0
Config.MaxPaintAreaHeight = 5.0
Config.MinPaintAreaSize = 0.3
Config.WallOffset = 0.005

-- Distances
Config.SelectionMaxDistance = 10.0
Config.PaintMaxDistance = 4.0
Config.RenderDistance = 50.0
Config.UnloadDistance = 80.0
Config.AutoSaveDistance = 15.0
Config.EraserMaxDistance = 4.0

-- Performance
Config.MaxActiveRenderers = 20
Config.RendererCheckInterval = 1000
Config.StrokeThrottleMs = 16

-- Brush Settings
Config.BrushSizes = {
    { name = 'THIN',   size = 4,  sprayDensity = 15 },
    { name = 'MEDIUM', size = 10, sprayDensity = 25 },
    { name = 'THICK',  size = 20, sprayDensity = 40 },
}
Config.DefaultBrushSizeIndex = 1
Config.DefaultDensity = 0.7
Config.PressureEnabled = true
Config.DefaultPressure = 0.8
Config.MinPressure = 0.3
Config.MaxPressure = 1.0

-- Colors
Config.DefaultColor = '#000000'
Config.ColorPresets = {
    '#000000', '#FFFFFF', '#FF0000', '#00FF00', '#0000FF',
    '#FFFF00', '#FF8800', '#8800FF', '#FF00AA', '#00FFFF',
    '#8B4513', '#808080'
}
Config.EnableColorPicker = true

-- Key Bindings
Config.Keys = {
    SelectCorner = 24, CancelSelection = 177, Paint = 24, Erase = 25,
    Validate = 191, Cancel = 177, Undo = -1, Redo = -1,
    ScrollUp = 241, ScrollDown = 242, ShakeCan = 47, ToggleMouse = 19,
    MoveForward = 172, MoveBackward = 173,
    EraseStroke = 24, ValidateErase = 191, CancelErase = 177
}
Config.PositionStepSize = 0.01
Config.DuiMoveMaxOffset = 0.3
Config.UndoKey = 0x5A
Config.RedoKey = 0x59

-- Stroke Limits
Config.MaxStrokesPerPainting = 500
Config.MaxPointsPerStroke = 5000
Config.MaxTotalPoints = 50000

-- Expiry System
Config.ExpiryEnabled = false
Config.ExpiryDays = 7
Config.ExpiryCheckInterval = 1800

-- Animations & Props
Config.SprayAnimation = {
    dict = 'anim@scripted@freemode@postertag@graffiti_spray@male@',
    anim = 'spray_can_idle_male',
    flag = 49,
}
Config.ShakeAnimation = {
    dict = 'anim@scripted@freemode@postertag@graffiti_spray@male@',
    anim = 'shake_can_male',
    duration = 2000,
}
Config.SprayCanProp = 'prop_cs_spray_can'
Config.ClothProp = 'v_res_fa_sponge01'
Config.SprayParticle = { dict = 'core', name = 'veh_respray_smoke', scale = 0.2, enabled = true }

-- Spray Realism
Config.SprayDistanceSpread = true
Config.SprayDistanceMinMult = 0.6
Config.SprayDistanceMaxMult = 2.5
Config.SprayVelocityFade = true
Config.SprayVelocityFadeMin = 0.15
Config.SprayVelocityFadeMax = 1.0
Config.SprayVelocityMaxSpeed = 300.0
Config.SpraySoundEnabled = true

-- Surfaces & Zones
Config.AllowedSurfaceMaterials = {}
Config.BlacklistedZones = {}

-- Discord Logging
Config.LogPaintCreate = true
Config.LogPaintDelete = true
Config.LogPaintErase = true
Config.LogAdminActions = true
Config.LogColors = { Create = 3066993, Delete = 15158332, Erase = 15105570, Admin = 3447003 }

-- Notification & UI
Config.NotifyDuration = 5000
Config.EraseAnimation = { dict = 'amb@world_human_maid_clean@base', anim = 'base', flag = 49 }
Config.LivePreviewEnabled = true
Config.LivePreviewInterval = 1000
Config.LivePreviewDistance = 30.0

-- Import / Export
Config.ImportExportEnabled = true
Config.ImportCommand = 'sprayimport'
Config.ExportCommand = 'sprayexport'
Config.ExportLimitPerUser = 10
Config.ExportLimitPerPainting = 3
Config.ExportLimitResetSeconds = 3600
