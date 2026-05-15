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

-- Paint Styles
Config.PaintStyles = {
    { id = 'spray',       name = 'Aerosol Spray',   icon = 'spray' },
    { id = 'pen',         name = 'Fine Marker',     icon = 'pen' },
    { id = 'calligraphy', name = 'Calligraphy',     icon = 'marker' },
    { id = 'splatter',    name = 'Splatter',        icon = 'tint' },
    { id = 'airbrush',    name = 'Soft Airbrush',   icon = 'cloud' },
    { id = 'drip',        name = 'Drip Style',      icon = 'tint' },
    { id = 'stencil',     name = 'Stencil Stamp',   icon = 'stencil' },
}
Config.DefaultPaintStyleIndex = 1

-- Drip Style Settings
Config.DripThresholdMs = 350 -- Time holding still before dripping
Config.DripSpeed = 5.0      -- How fast the drip falls
Config.DripWidthMult = 0.5  -- Width of the drip relative to brush size
Config.DripMaxLen = 180     -- Max length of a single drip
Config.DripTolerance = 15.0 -- Movement tolerance for dwelling (pixels)

-- Stencils
Config.Stencils = {
    { name = 'Peak',   points = { {x=0,y=-10},{x=10,y=10},{x=-10,y=10},{x=0,y=-10} } },
    { name = 'Star',   points = { {x=0,y=-15},{x=4,y=-5},{x=15,y=-5},{x=7,y=2},{x=10,y=12},{x=0,y=5},{x=-10,y=12},{x=-7,y=2},{x=-15,y=-5},{x=-4,y=-5},{x=0,y=-15} } },
    { name = 'Crown',  points = { {x=-10,y=5},{x=-10,y=-5},{x=-5,y=0},{x=0,y=-10},{x=5,y=0},{x=10,y=-5},{x=10,y=5},{x=-10,y=5} } },
    { name = 'Skull',  points = { {x=-5,y=-8},{x=5,y=-8},{x=8,y=-3},{x=8,y=3},{x=4,y=10},{x=2,y=10},{x=2,y=6},{x=-2,y=6},{x=-2,y=10},{x=-4,y=10},{x=-8,y=3},{x=-8,y=-3},{x=-5,y=-8} } },
    { name = 'Heart',  points = { {x=0,y=10},{x=-10,y=0},{x=-10,y=-5},{x=-5,y=-10},{x=0,y=-5},{x=5,y=-10},{x=10,y=-5},{x=10,y=0},{x=0,y=10} } },
}
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
    SelectCorner = 24, CancelSelection = 178, Paint = 24, Erase = 25,
    Validate = 191, Cancel = 178, Undo = -1, Redo = -1,
    ScrollUp = 241, ScrollDown = 242, ShakeCan = 47, ToggleMouse = 19,
    MoveForward = 172, MoveBackward = 173,
    EraseStroke = 24, ValidateErase = 191, CancelErase = 178
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

-- Image Sprays
Config.ImageSpraysEnabled = true
Config.ImageAllowedHosts = {
    'i.imgur.com',
    'media.discordapp.net',
    'cdn.discordapp.com',
    'images.unsplash.com'
}
Config.ImageMaxPerSpray = 5
Config.ImageDefaultSize = 256
Config.ImageMinScale = 0.25
Config.ImageMaxScale = 4.0
Config.ImageUrlMaxLength = 512

-- Text Scenes & Signs
Config.ScenesEnabled = true
Config.SceneUseCommand = true
Config.SceneUseItem = false
Config.SceneDeleteCommandName = 'deletescene'
Config.SceneHideCommandName = 'hidescenes'
Config.SceneMaxTextLength = 200
Config.ScenePlacementDistance = 8.0
Config.SceneDefaultDistance = 10.0
Config.SceneDefaultCloseDistance = 3.0
Config.SceneDefaultHours = 24
Config.SceneAllowPermanentAdmin = true
Config.SceneExpiryCheckInterval = 60
Config.SceneMaxActiveRenderers = 25
Config.SceneRendererWidth = 1280
Config.SceneRendererHeight = 720
Config.SceneScale = 0.1
Config.SceneTextItemConsume = false
Config.SceneSignItemConsume = false
Config.SceneAccentColor = '#87da21'
Config.SceneFonts = {
    'Geist', 'Oswald', 'Montserrat', 'Lato', 'Merriweather', 'Raleway',
    'Lobster', 'Creepster', 'Rock Salt', 'Nosifer'
}
Config.SceneBackgrounds = {
    'empty', 'solid', 'sticky', 'oldPaper', 'oldPaper2', 'oldPaper3',
    'tornPaper', 'warning', 'wood', 'water', 'blood', 'blueprint'
}
Config.ScenePresets = {
    {
        name = 'Default Scene',
        text = 'This is a scene.',
        font = 'Oswald',
        fontSize = 48,
        fontColor = '#ffffff',
        fontOutline = 'none',
        fontOutlineColor = '#000000',
        fontStyle = 'normal',
        background = 'empty',
        backgroundFill = 'contain',
        backgroundOffsetX = 50,
        backgroundOffsetY = 50,
        backgroundSizeX = 100,
        backgroundSizeY = 100,
        backgroundColor = '#262626',
        rotationType = 'rotateGround',
        distance = 10,
        closeDistance = 3,
        hoursVisible = 24,
        visibility = 'always'
    },
    {
        name = 'Simple Sign',
        text = 'NOTICE',
        font = 'Geist',
        fontSize = 54,
        fontColor = '#111827',
        fontOutline = 'none',
        fontOutlineColor = '#000000',
        fontStyle = 'bold',
        background = 'solid',
        backgroundFill = 'contain',
        backgroundOffsetX = 50,
        backgroundOffsetY = 50,
        backgroundSizeX = 100,
        backgroundSizeY = 100,
        backgroundColor = '#f8fafc',
        rotationType = 'rotateGround',
        distance = 12,
        closeDistance = 3,
        hoursVisible = 168,
        visibility = 'always'
    }
}
