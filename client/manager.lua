Peak = Peak or {}

-- ============================================================
-- STATE MANAGEMENT
-- ============================================================

SprayState = {
    mode = "idle",
    corner1 = nil,
    corner2 = nil,
    surfaceNormal = nil,
    corners = nil,
    rightAxis = nil,
    upAxis = nil,
    currentColor = Config.DefaultColor,
    forcedColor = nil,
    brushIndex = Config.DefaultBrushSizeIndex,
    pressure = Config.DefaultPressure,
    strokeCount = 0,
    totalPoints = 0,
    duiObject = nil,
    duiTxd = nil,
    duiTxn = nil,
    isDrawing = false,
    lastStrokeTime = 0,
    propEntity = nil,
    ptfxHandle = nil,
    soundId = nil,
    strokeHistory = {},
    redoStack = {},
    paintingId = nil,
    targetPaintingCorners = nil,
    targetPaintingRight = nil,
    targetPaintingUp = nil,
    pendingValidate = false,
    pendingCancel = false,
}

KnownPaintings = {}

-- ============================================================
-- INITIALIZATION
-- ============================================================

CreateThread(function()
    while not Peak.Client or not Peak.Client.Ready do
        Wait(500)
    end

    local paintings = Peak.Client.TriggerCallback("peak-sprays:getPaintings")
    if paintings then
        for _, p in ipairs(paintings) do
            KnownPaintings[p.id] = {
                id = p.id,
                corners = SprayUtils.TableToCorners(p.corners),
                normal = SprayUtils.TableToVec3(p.normal),
                center = vector3(p.world_x, p.world_y, p.world_z),
                canvasWidth = p.canvas_width,
                canvasHeight = p.canvas_height,
                strokeCount = p.stroke_count,
                duiObj = nil,
                txdName = nil,
                txnName = nil,
                loaded = false,
                renderState = "idle"
            }
        end
        SprayUtils.DebugPrint("Loaded " .. #paintings .. " paintings from server")
    end
end)

-- ============================================================
-- ITEM & COMMAND HANDLING
-- ============================================================

if Config.UseItem then
    RegisterNetEvent("peak-sprays:useSprayPaint", function(itemName)
        if SprayState.mode ~= "idle" then return end

        local color = Config.ColoredItems[itemName]
        StartSelectionMode(color)
    end)

    RegisterNetEvent("peak-sprays:useCloth", function()
        if SprayState.mode ~= "idle" then return end
        StartEraserMode()
    end)
end

if Config.UseCommand then
    RegisterCommand(Config.CommandName, function()
        if SprayState.mode ~= "idle" then return end

        if not Peak.Client.TriggerCallback("peak-sprays:hasSprayItem") then
            Peak.Client.Notify(L("no_item"), "error", Config.NotifyDuration)
            return
        end
        StartSelectionMode(nil)
    end, false)

    RegisterCommand(Config.EraseCommandName, function()
        if SprayState.mode ~= "idle" then return end

        if not Peak.Client.TriggerCallback("peak-sprays:hasClothItem") then
            Peak.Client.Notify(L("no_cloth"), "error", Config.NotifyDuration)
            return
        end
        StartEraserMode()
    end, false)
end

-- ============================================================
-- SELECTION MODE
-- ============================================================

--- Starts the area selection mode for a new painting.
--- @param forcedColor string|nil Hex color if using a colored item
function StartSelectionMode(forcedColor)
    if not CanSpray() then
        SprayUtils.DebugPrint("[Spray] CanSpray() returned false, blocking spray")
        return
    end

    SprayUtils.DebugPrint("[Selection] Starting selection mode, forcedColor:", tostring(forcedColor))

    SprayState.mode = "selecting"
    SprayState.corner1 = nil
    SprayState.corner2 = nil
    SprayState.surfaceNormal = nil
    SprayState.forcedColor = forcedColor
    SprayState.currentColor = forcedColor or Config.DefaultColor
    SprayState.brushIndex = Config.DefaultBrushSizeIndex

    SetFollowPedCamViewMode(4)
    Peak.Client.Notify(L("select_first_corner"), "info", Config.NotifyDuration)

    CreateThread(SelectionLoop)
end

function SelectionLoop()
    local selectionStep = 1
    local activeNormal = nil
    local isControlPressed = false

    while SprayState.mode == "selecting" do
        Wait(0)
        local ped = PlayerPedId()

        SetFollowPedCamViewMode(4)

        -- Disable controls
        for _, control in ipairs({0, 24, 25, 47, 58, 140, 141, 142, 257, 263, 264}) do
            DisableControlAction(0, control, true)
        end
        DisablePlayerFiring(ped, true)

        local hit, hitCoords, normal, _ = RaycastModule.FromCamera(Config.SelectionMaxDistance)
        if hit then
            RaycastModule.DrawCrosshair(hitCoords, 255, 255, 255)

            if selectionStep == 2 and SprayState.corner1 then
                local rect, right, up = RaycastModule.ComputeRectangle(SprayState.corner1, hitCoords, activeNormal)
                RaycastModule.DrawRectOutline(rect, 255, 0, 0, 200)
            end

            if IsDisabledControlJustPressed(0, Config.Keys.SelectCorner) and not isControlPressed then
                isControlPressed = true

                if SprayUtils.IsInBlacklistedZone(hitCoords) then
                    Peak.Client.Notify(L("blacklisted_zone"), "error", Config.NotifyDuration)
                elseif selectionStep == 1 then
                    SprayState.corner1 = hitCoords
                    SprayState.surfaceNormal = normal
                    activeNormal = normal
                    selectionStep = 2
                    Peak.Client.Notify(L("select_second_corner"), "info", Config.NotifyDuration)
                    SprayUtils.DebugPrint("Corner 1 placed at", hitCoords)
                elseif selectionStep == 2 then
                    SprayState.corner2 = hitCoords
                    local rect, right, up = RaycastModule.ComputeRectangle(SprayState.corner1, SprayState.corner2, activeNormal)

                    local width = #(rect.bottomRight - rect.bottomLeft)
                    local height = #(rect.topLeft - rect.bottomLeft)

                    if width < Config.MinPaintAreaSize or height < Config.MinPaintAreaSize then
                        Peak.Client.Notify(L("area_too_small"), "error", Config.NotifyDuration)
                        selectionStep = 1
                        SprayState.corner1 = nil
                    else
                        local ok, err = RaycastModule.ValidateCorners(rect, activeNormal, 0.5)
                        if not ok then
                            Peak.Client.Notify(L(err), "error", Config.NotifyDuration)
                            selectionStep = 1
                            SprayState.corner1 = nil
                        else
                            SprayState.corners = rect
                            SprayState.rightAxis = right
                            SprayState.upAxis = up
                            SprayUtils.DebugPrint("Rectangle validated, entering paint mode")
                            StartPaintingMode()
                            return
                        end
                    end
                end
            end

            if not IsDisabledControlPressed(0, Config.Keys.SelectCorner) then
                isControlPressed = false
            end
        else
            isControlPressed = false
        end

        if SprayState.pendingCancel then
            SprayState.pendingCancel = false
            CancelSelection()
            return
        end

        if SprayState.corner1 and selectionStep == 2 then
            RaycastModule.DrawCrosshair(SprayState.corner1, 0, 255, 0)
        end
    end
end

function CancelSelection()
    SprayState.mode = "idle"
    SprayState.corner1 = nil
    SprayState.corner2 = nil
    SprayState.surfaceNormal = nil
    SprayState.forcedColor = nil
    Peak.Client.Notify(L("selection_cancelled"), "info", Config.NotifyDuration)
end

-- ============================================================
-- PROP & ASSET HANDLING
-- ============================================================

function AttachSprayCanProp()
    local ped = PlayerPedId()
    Peak.Client.LoadModel(Config.SprayCanProp)

    local hash = GetHashKey(Config.SprayCanProp)
    local obj = CreateObject(hash, 0.0, 0.0, 0.0, true, true, false)
    -- Attachment for spray can (pointing towards the wall)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, 57005), 0.11, 0.02, -0.02, 20.0, 70.0, 70.0, 0, true, false, true, 2, true)
    SprayState.propEntity = obj
    SetModelAsNoLongerNeeded(hash)
    return obj
end

function AttachClothProp()
    local ped = PlayerPedId()
    Peak.Client.LoadModel(Config.ClothProp)

    local hash = GetHashKey(Config.ClothProp)
    local obj = CreateObject(hash, 0.0, 0.0, 0.0, true, true, false)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, 28422), 0.0, 0.0022, -0.0227, 0.0, 180.0, 0.0, true, true, false, true, 1, true)
    SprayState.propEntity = obj
    SetModelAsNoLongerNeeded(hash)
    return obj
end

function DetachProp()
    if SprayState.propEntity and DoesEntityExist(SprayState.propEntity) then
        DeleteObject(SprayState.propEntity)
    end
    SprayState.propEntity = nil
end

-- ============================================================
-- CLEANUP
-- ============================================================

--- Fully resets the spray state and cleans up all temporary objects/effects.
function FullCleanup()
    SprayUtils.DebugPrint("[Cleanup] Full cleanup initiated, mode was:", SprayState.mode)
    StopSprayParticle()
    StopSpraySound()
    DetachProp()
    ClearPedTasks(PlayerPedId())

    if SprayState.duiObject then
        DestroyDui(SprayState.duiObject)
        SprayState.duiObject = nil
    end

    SprayState.mode = "idle"
    SprayState.corner1 = nil
    SprayState.corner2 = nil
    SprayState.surfaceNormal = nil
    SprayState.corners = nil
    SprayState.rightAxis = nil
    SprayState.upAxis = nil
    SprayState.forcedColor = nil
    SprayState.isDrawing = false
    SprayState.strokeCount = 0
    SprayState.totalPoints = 0
    SprayState.strokeHistory = {}
    SprayState.redoStack = {}
    SprayState.paintingId = nil
    SprayState.targetPaintingCorners = nil
    SprayState.targetPaintingRight = nil
    SprayState.targetPaintingUp = nil
    SprayState.pendingValidate = false
    SprayState.pendingCancel = false

    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SprayState._nuiMouseActive = false
    SendNUIMessage({ action = "closeHUD" })
end

-- ============================================================
-- EVENTS
-- ============================================================

RegisterNetEvent("peak-sprays:cl:newPainting", function(data)
    KnownPaintings[data.id] = {
        id = data.id,
        corners = SprayUtils.TableToCorners(data.corners),
        normal = SprayUtils.TableToVec3(data.normal),
        center = vector3(data.world_x, data.world_y, data.world_z),
        canvasWidth = data.canvas_width,
        canvasHeight = data.canvas_height,
        strokeCount = data.stroke_count,
        duiObj = nil,
        txdName = nil,
        txnName = nil,
        loaded = false,
        renderState = "idle"
    }
end)

RegisterNetEvent("peak-sprays:cl:removePainting", function(id)
    local p = KnownPaintings[id]
    if p then
        if p.duiObj then DestroyDui(p.duiObj) end
        KnownPaintings[id] = nil
    end
end)

RegisterNetEvent("peak-sprays:cl:updatePainting", function(data)
    local p = KnownPaintings[data.id]
    if p then
        p.strokeCount = data.stroke_count
        if p.duiObj then
            DestroyDui(p.duiObj)
            p.duiObj = nil
        end
        p.loaded = false
        p.renderState = "idle"
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    FullCleanup()
    for _, p in pairs(KnownPaintings) do
        if p.duiObj then DestroyDui(p.duiObj) end
    end
end)

-- ============================================================
-- NUI CALLBACKS
-- Handle fetchNui() calls from the Vue HUD
-- ============================================================

RegisterNUICallback("releaseMouse", function(_, cb)
    if SprayState._nuiMouseActive then
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        SprayState._nuiMouseActive = false
    end
    cb("ok")
end)

RegisterNUICallback("confirmSpray", function(_, cb)
    if SprayState._nuiMouseActive then
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        SprayState._nuiMouseActive = false
    end
    if SprayState.mode == "painting" then
        ValidatePainting()
    elseif SprayState.mode == "erasing" then
        ValidateErase()
    end
    cb("ok")
end)

RegisterNUICallback("cancelSpray", function(_, cb)
    if SprayState._nuiMouseActive then
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        SprayState._nuiMouseActive = false
    end
    if SprayState.mode == "painting" then
        CancelPainting()
    elseif SprayState.mode == "erasing" then
        CancelErase()
    elseif SprayState.mode == "selecting" then
        CancelSelection()
    end
    cb("ok")
end)

RegisterNUICallback("changeColor", function(data, cb)
    if data and data.color and not SprayState.forcedColor then
        SprayState.currentColor = data.color
    end
    cb("ok")
end)

RegisterNUICallback("changeDensity", function(data, cb)
    if data and data.density then
        SprayState.density = SprayUtils.Clamp(tonumber(data.density) or 0.7, 0.0, 1.0)
    end
    cb("ok")
end)

RegisterNUICallback("uiExportPainting", function(_, cb)
    if SprayState.mode == "painting" and SprayState.strokeHistory and #SprayState.strokeHistory > 0 then
        local result = Peak.Client.TriggerCallback("peak-sprays:exportCurrentStrokes", {
            strokeData    = SprayState.strokeHistory,
            canvasWidth   = SprayState.canvasWidth or Config.CanvasWidth,
            canvasHeight  = SprayState.canvasHeight or Config.CanvasHeight,
        })
        if result and result.success and result.code then
            SendNUIMessage({ action = "exportResult", code = result.code })
            SendNUIMessage({ action = "copyToClipboard", text = result.code })
        end
    end
    cb("ok")
end)

RegisterNUICallback("uiImportPainting", function(data, cb)
    if SprayState.mode == "painting" and data and data.code and SprayState.duiObject then
        local result = Peak.Client.TriggerCallback("peak-sprays:importPainting", data.code)
        if result and result.success and result.strokeData then
            SendDuiMessage(SprayState.duiObject, json.encode({ action = "clear" }))
            SendDuiMessage(SprayState.duiObject, json.encode({
                action  = "loadStrokes",
                strokes = result.strokeData,
            }))
            SprayState.strokeHistory = result.strokeData
            SprayState.strokeCount   = #result.strokeData
            SprayState.totalPoints   = 0
            for _, s in ipairs(SprayState.strokeHistory) do
                SprayState.totalPoints = SprayState.totalPoints + ((s.points and #s.points) or 0)
            end
            SendNUIMessage({
                action      = "strokeUpdate",
                strokeCount = SprayState.strokeCount,
                maxStrokes  = Config.MaxStrokesPerPainting,
                canUndo     = #SprayState.strokeHistory > 0,
                canRedo     = false,
            })
        else
            Peak.Client.Notify((result and result.message) or "Invalid import code", "error", Config.NotifyDuration)
        end
    end
    cb("ok")
end)

RegisterNUICallback("copyResult", function(_, cb)
    cb("ok")
end)
