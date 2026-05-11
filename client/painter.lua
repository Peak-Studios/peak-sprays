local activeDuiId = 0

-- ============================================================
-- PAINTING INITIALIZATION
-- ============================================================

--- Enters the active painting mode, initializing DUI and UI HUD.
function StartPaintingMode()
    SprayUtils.DebugPrint("[Paint] Entering painting mode")
    SprayState.mode = "painting"
    SprayState.strokeCount = 0
    SprayState.totalPoints = 0
    SprayState.strokeHistory = {}
    SprayState.redoStack = {}
    SprayState.isDrawing = false
    SprayState.density = Config.DefaultDensity or 0.7

    activeDuiId = activeDuiId + 1
    SprayState.duiTxd = "peak_spray_active_" .. activeDuiId .. "_dict"
    SprayState.duiTxn = "peak_spray_active_" .. activeDuiId

    local width = #(SprayState.corners.bottomRight - SprayState.corners.bottomLeft)
    local height = #(SprayState.corners.topLeft - SprayState.corners.bottomLeft)

    -- Calculate canvas aspect ratio
    local resX, resY = Config.CanvasWidth, Config.CanvasHeight
    if width > height then
        resY = math.floor(Config.CanvasWidth * (height / width))
    else
        resX = math.floor(Config.CanvasHeight * (width / height))
    end

    SprayState.canvasWidth = resX
    SprayState.canvasHeight = resY

    local url = ("nui://%s/ui/dist/canvas.html?width=%d&height=%d"):format(GetCurrentResourceName(), resX, resY)
    local dui = CreateDui(url, resX, resY)
    SprayState.duiObject = dui

    -- Wait for DUI to be ready
    local timeout = 500
    while not IsDuiAvailable(dui) and timeout > 0 do
        Wait(10)
        timeout = timeout - 1
    end

    local txd = CreateRuntimeTxd(SprayState.duiTxd)
    local handle = GetDuiHandle(dui)

    if handle and handle ~= "" then
        CreateRuntimeTextureFromDuiHandle(txd, SprayState.duiTxn, handle)
    else
        Peak.Client.Notify(L("painting_cancelled") or "Failed to load painting canvas.", "error", Config.NotifyDuration)
        CancelPainting()
        return
    end

    -- Initialize DUI state
    SetTimeout(800, function()
        if SprayState.duiObject then
            SendDuiMessage(SprayState.duiObject, json.encode({
                action = "init",
                width = resX,
                height = resY
            }))
        end
    end)

    Peak.Client.LoadAnimDict(Config.SprayAnimation.dict)
    Peak.Client.LoadAnimDict(Config.ShakeAnimation.dict)

    if Config.SprayParticle.enabled then
        RequestNamedPtfxAsset(Config.SprayParticle.dict)
    end

    AttachSprayCanProp()
    TaskPlayAnim(PlayerPedId(), Config.SprayAnimation.dict, Config.SprayAnimation.anim, 8.0, -8.0, -1, Config.SprayAnimation.flag, 0, false, false, false)

    SendNUIMessage({
        action = "openHUD",
        brushSizes = Config.BrushSizes,
        currentBrushIndex = SprayState.brushIndex,
        currentColor = SprayState.currentColor,
        forcedColor = SprayState.forcedColor,
        colorPresets = Config.ColorPresets,
        enableColorPicker = Config.EnableColorPicker and not SprayState.forcedColor,
        pressure = SprayState.pressure,
        density = SprayState.density,
        pressureEnabled = Config.PressureEnabled,
        importExportEnabled = Config.ImportExportEnabled,
        keys = {
            mouse = "ALT",
            shake = "G",
            size = "SCROLL",
            paint = "LMB",
            erase = "RMB",
            validate = "ENTER",
            cancel = "DEL",
            undo = "Z",
            redo = "Y",
            forward = "↑",
            backward = "↓"
        }
    })

    Peak.Client.Notify(L("painting_started"), "success", Config.NotifyDuration)

    CreateThread(PaintingControlDisableLoop)
    CreateThread(PaintingRenderLoop)
    CreateThread(PaintingInputLoop)
    CreateThread(PaintingDistanceCheck)

    if Config.LivePreviewEnabled then
        StartLivePreviewLoop()
    end
end

-- ============================================================
-- LOOPS
-- ============================================================

function PaintingControlDisableLoop()
    while SprayState.mode == "painting" do
        Wait(0)
        local ped = PlayerPedId()
        SetFollowPedCamViewMode(4)

        -- Disable controls
        for _, control in ipairs({0, 24, 25, 44, 37, 47, 58, 69, 75, 91, 92, 114, 140, 141, 142, 257, 263, 264, 172, 173, 19}) do
            DisableControlAction(0, control, true)
        end
        DisablePlayerFiring(ped, true)
    end
end

function PaintingRenderLoop()
    while SprayState.mode == "painting" do
        Wait(0)
        local corners = SprayState.corners
        if corners and SprayState.duiObject then
            local hit, hitCoords, camCoord = RaycastModule.FromCameraToPlane(corners.bottomLeft, SprayState.surfaceNormal, Config.PaintMaxDistance)
            if hit then
                local pedCoords = GetEntityCoords(PlayerPedId())
                local dist = #(pedCoords - hitCoords)
                local distMult = math.min(dist / Config.PaintMaxDistance, 1.0)

                local spreadMult = 1.0
                if Config.SprayDistanceSpread then
                    spreadMult = Config.SprayDistanceMinMult + (Config.SprayDistanceMaxMult - Config.SprayDistanceMinMult) * distMult
                end

                local brush = Config.BrushSizes[SprayState.brushIndex]
                local visualSize = brush.size * spreadMult

                -- Draw crosshair/brush preview
                local width = #(corners.bottomRight - corners.bottomLeft)
                local canvasScale = visualSize / Config.CanvasWidth * width * 0.5
                if canvasScale < 0.005 then canvasScale = 0.005 end

                local right = norm(corners.bottomRight - corners.bottomLeft)
                local up = norm(corners.topLeft - corners.bottomLeft)

                -- Draw Circle preview
                local segments = 24
                local step = (2.0 * math.pi) / segments
                for i = 0, segments - 1 do
                    local angle1 = i * step
                    local angle2 = (i + 1) * step
                    local p1 = hitCoords + right * (math.cos(angle1) * canvasScale) + up * (math.sin(angle1) * canvasScale)
                    local p2 = hitCoords + right * (math.cos(angle2) * canvasScale) + up * (math.sin(angle2) * canvasScale)
                    DrawLine(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, 255, 255, 255, 220)
                end

                -- Center dot
                local dotSize = 0.005
                DrawLine(hitCoords.x - right.x * dotSize, hitCoords.y - right.y * dotSize, hitCoords.z - right.z * dotSize, hitCoords.x + right.x * dotSize, hitCoords.y + right.y * dotSize, hitCoords.z + right.z * dotSize, 255, 255, 255, 255)
                DrawLine(hitCoords.x - up.x * dotSize, hitCoords.y - up.y * dotSize, hitCoords.z - up.z * dotSize, hitCoords.x + up.x * dotSize, hitCoords.y + up.y * dotSize, hitCoords.z + up.z * dotSize, 255, 255, 255, 255)
            end

            -- Render active canvas
            DrawSpritePoly(
                corners.topLeft.x, corners.topLeft.y, corners.topLeft.z,
                corners.topRight.x, corners.topRight.y, corners.topRight.z,
                corners.bottomRight.x, corners.bottomRight.y, corners.bottomRight.z,
                255, 255, 255, 255,
                SprayState.duiTxd, SprayState.duiTxn,
                0.0, 0.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0
            )
            DrawSpritePoly(
                corners.topLeft.x, corners.topLeft.y, corners.topLeft.z,
                corners.bottomRight.x, corners.bottomRight.y, corners.bottomRight.z,
                corners.bottomLeft.x, corners.bottomLeft.y, corners.bottomLeft.z,
                255, 255, 255, 255,
                SprayState.duiTxd, SprayState.duiTxn,
                0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0
            )
            RaycastModule.DrawRectOutline(corners, 255, 0, 0, 150)
        end
    end
end

function PaintingInputLoop()
    while SprayState.mode == "painting" do
        Wait(0)
        local time = GetGameTimer()

        if IsDisabledControlJustPressed(0, Config.Keys.ToggleMouse) then
            if GetGameTimer() - (SprayState.lastMouseToggleTime or 0) > 300 then
                ToggleNuiMouse()
                SprayState.lastMouseToggleTime = GetGameTimer()
            end
        end

        if SprayState._nuiMouseActive then
            if SprayState.isDrawing then
                EndCurrentStroke()
                SprayState._eraseMode = false
            end
        else
            if IsDisabledControlPressed(0, 24) then
                HandlePaintInput(time)
            else
                if SprayState.isDrawing and not SprayState._eraseMode then
                    EndCurrentStroke()
                end
            end

            if IsDisabledControlPressed(0, 25) then
                HandleEraseInput(time)
            else
                if SprayState.isDrawing and SprayState._eraseMode then
                    EndCurrentStroke()
                    SprayState._eraseMode = false
                end
            end

            if IsControlJustPressed(0, 241) then -- Scroll Up
                CycleBrushSize(1)
            elseif IsControlJustPressed(0, 242) then -- Scroll Down
                CycleBrushSize(-1)
            end

            if IsDisabledControlJustPressed(0, Config.Keys.MoveForward) then
                MoveDuiSurface(Config.PositionStepSize)
            elseif IsDisabledControlJustPressed(0, Config.Keys.MoveBackward) then
                MoveDuiSurface(-Config.PositionStepSize)
            end
        end

        if SprayState.pendingValidate then
            SprayState.pendingValidate = false
            SprayState.pendingCancel = false
            ValidatePainting()
            return
        end

        if SprayState.pendingCancel then
            SprayState.pendingCancel = false
            CancelPainting()
            return
        end
    end
end

-- ============================================================
-- INPUT HANDLING
-- ============================================================

function HandlePaintInput(time)
    if time - SprayState.lastStrokeTime < Config.StrokeThrottleMs then return end
    SprayState.lastStrokeTime = time

    local hit, hitCoords = RaycastModule.FromCameraToPlane(SprayState.corners.bottomLeft, SprayState.surfaceNormal, Config.PaintMaxDistance)
    if not hit then
        if SprayState.isDrawing then EndCurrentStroke() end
        return
    end

    local _, u, v = RaycastModule.WorldToCanvas(hitCoords, SprayState.corners, SprayState.rightAxis, SprayState.upAxis)
    if not _ then
        if SprayState.isDrawing then EndCurrentStroke() end
        return
    end

    local x = u * (SprayState.canvasWidth or Config.CanvasWidth)
    local y = (1.0 - v) * (SprayState.canvasHeight or Config.CanvasHeight)

    local pedCoords = GetEntityCoords(PlayerPedId())
    local distMult = math.min(#(pedCoords - hitCoords) / Config.PaintMaxDistance, 1.0)

    local pressure = SprayState.pressure
    if Config.PressureEnabled then
        pressure = SprayUtils.Clamp(1.0 - distMult * 0.5, Config.MinPressure, Config.MaxPressure)
    end

    local spreadMult = 1.0
    if Config.SprayDistanceSpread then
        spreadMult = Config.SprayDistanceMinMult + (Config.SprayDistanceMaxMult - Config.SprayDistanceMinMult) * distMult
    end

    local brush = Config.BrushSizes[SprayState.brushIndex]
    local size = math.floor(brush.size * spreadMult)
    local density = SprayState.density or 0.7
    local scatterCount = math.max(1, math.floor(brush.sprayDensity * spreadMult * density))
    local finalPressure = pressure

    if not SprayState.isDrawing then
        if SprayState.strokeCount >= Config.MaxStrokesPerPainting then
            Peak.Client.Notify(L("max_strokes_reached"), "warning", Config.NotifyDuration)
            return
        end

        SprayState.isDrawing = true
        SprayState._eraseMode = false
        SprayState.redoStack = {}

        local newStroke = {
            type = "paint",
            color = SprayState.currentColor,
            size = size,
            density = scatterCount,
            pressure = finalPressure,
            scatter = density,
            points = {{ x = x, y = y }}
        }
        table.insert(SprayState.strokeHistory, newStroke)
        SprayState.strokeCount = SprayState.strokeCount + 1

        SendDuiMessage(SprayState.duiObject, json.encode({
            action = "startStroke",
            type = "paint",
            x = x,
            y = y,
            color = SprayState.currentColor,
            size = size,
            density = scatterCount,
            pressure = finalPressure,
            scatter = density
        }))
        StartSpraySound()
        StartSprayParticle(SprayState.currentColor)
    else
        local currentStroke = SprayState.strokeHistory[#SprayState.strokeHistory]
        if currentStroke then
            if #currentStroke.points >= Config.MaxPointsPerStroke then
                EndCurrentStroke()
                return
            end
            if SprayState.totalPoints >= Config.MaxTotalPoints then
                Peak.Client.Notify(L("max_points_reached"), "warning", 3000)
                EndCurrentStroke()
                return
            end

            table.insert(currentStroke.points, { x = x, y = y })
            SprayState.totalPoints = SprayState.totalPoints + 1

            SendDuiMessage(SprayState.duiObject, json.encode({
                action = "addPoint",
                x = x,
                y = y,
                pressure = finalPressure,
                size = size,
                density = scatterCount
            }))
        end
    end
end

function HandleEraseInput(time)
    if time - SprayState.lastStrokeTime < Config.StrokeThrottleMs then return end
    SprayState.lastStrokeTime = time

    local hit, hitCoords = RaycastModule.FromCameraToPlane(SprayState.corners.bottomLeft, SprayState.surfaceNormal, Config.PaintMaxDistance)
    if not hit then
        if SprayState.isDrawing and SprayState._eraseMode then
            EndCurrentStroke()
            SprayState._eraseMode = false
        end
        return
    end

    local _, u, v = RaycastModule.WorldToCanvas(hitCoords, SprayState.corners, SprayState.rightAxis, SprayState.upAxis)
    if not _ then
        if SprayState.isDrawing and SprayState._eraseMode then
            EndCurrentStroke()
            SprayState._eraseMode = false
        end
        return
    end

    local x = u * (SprayState.canvasWidth or Config.CanvasWidth)
    local y = (1.0 - v) * (SprayState.canvasHeight or Config.CanvasHeight)
    local brush = Config.BrushSizes[SprayState.brushIndex]

    if SprayState.isDrawing and not SprayState._eraseMode then
        EndCurrentStroke()
    end

    if not SprayState.isDrawing then
        if SprayState.strokeCount >= Config.MaxStrokesPerPainting then
            Peak.Client.Notify(L("max_strokes_reached"), "warning", Config.NotifyDuration)
            return
        end

        SprayState.isDrawing = true
        SprayState._eraseMode = true
        SprayState.redoStack = {}

        local newStroke = {
            type = "erase",
            size = brush.size * 1.5,
            points = {{ x = x, y = y }}
        }
        table.insert(SprayState.strokeHistory, newStroke)
        SprayState.strokeCount = SprayState.strokeCount + 1

        SendDuiMessage(SprayState.duiObject, json.encode({
            action = "startStroke",
            type = "erase",
            x = x,
            y = y,
            size = brush.size * 1.5
        }))
    else
        local currentStroke = SprayState.strokeHistory[#SprayState.strokeHistory]
        if currentStroke then
            if SprayState.totalPoints >= Config.MaxTotalPoints then
                EndCurrentStroke()
                SprayState._eraseMode = false
                return
            end

            table.insert(currentStroke.points, { x = x, y = y })
            SprayState.totalPoints = SprayState.totalPoints + 1

            SendDuiMessage(SprayState.duiObject, json.encode({
                action = "addPoint",
                x = x,
                y = y
            }))
        end
    end
end

function EndCurrentStroke()
    if not SprayState.isDrawing then return end
    SprayState.isDrawing = false

    if SprayState.duiObject then
        SendDuiMessage(SprayState.duiObject, json.encode({ action = "endStroke" }))
    end

    StopSprayParticle()
    StopSpraySound()

    SendNUIMessage({
        action = "strokeUpdate",
        strokeCount = SprayState.strokeCount,
        maxStrokes = Config.MaxStrokesPerPainting,
        canUndo = #SprayState.strokeHistory > 0,
        canRedo = #SprayState.redoStack > 0
    })
end

-- ============================================================
-- ACTIONS
-- ============================================================

function ValidatePainting()
    if SprayState.mode ~= "painting" then return end

    if SprayState.isDrawing then EndCurrentStroke() end
    if #SprayState.strokeHistory == 0 then
        CancelPainting()
        return
    end

    local center = SprayUtils.GetCenterFromCorners(SprayState.corners)
    local data = {
        corners = SprayUtils.CornersToTable(SprayState.corners),
        normal = SprayUtils.Vec3ToTable(SprayState.surfaceNormal),
        strokeData = SprayState.strokeHistory,
        canvasWidth = Config.CanvasWidth,
        canvasHeight = Config.CanvasHeight,
        worldX = center.x,
        worldY = center.y,
        worldZ = center.z,
        strokeCount = SprayState.strokeCount
    }

    local result = Peak.Client.TriggerCallback("peak-sprays:savePainting", data)
    if result and result.success then
        Peak.Client.Notify(L("painting_saved"), "success", Config.NotifyDuration)
        if OnSprayCompleted then OnSprayCompleted(result.id, center) end
    else
        Peak.Client.Notify(result and result.message or "Error saving painting", "error", Config.NotifyDuration)
    end

    FullCleanup()
end

function CancelPainting()
    if SprayState.mode ~= "painting" then return end
    if SprayState.isDrawing then EndCurrentStroke() end
    Peak.Client.Notify(L("painting_cancelled"), "info", Config.NotifyDuration)
    FullCleanup()
end

function CycleBrushSize(delta)
    SprayState.brushIndex = SprayState.brushIndex + delta
    if SprayState.brushIndex > #Config.BrushSizes then
        SprayState.brushIndex = 1
    elseif SprayState.brushIndex < 1 then
        SprayState.brushIndex = #Config.BrushSizes
    end

    local brush = Config.BrushSizes[SprayState.brushIndex]
    SendNUIMessage({
        action = "brushChanged",
        brushName = brush.name,
        brushSize = brush.size,
        brushIndex = SprayState.brushIndex
    })
end

function MoveDuiSurface(step)
    if not SprayState.surfaceNormal or not SprayState.corners then return end

    local offset = SprayState._duiOffset or 0
    local newOffset = offset + step
    local maxOffset = Config.DuiMoveMaxOffset or 0.5

    if math.abs(newOffset) > maxOffset then return end

    SprayState._duiOffset = newOffset
    local moveVec = SprayState.surfaceNormal * step

    SprayState.corners.topLeft = SprayState.corners.topLeft + moveVec
    SprayState.corners.topRight = SprayState.corners.topRight + moveVec
    SprayState.corners.bottomLeft = SprayState.corners.bottomLeft + moveVec
    SprayState.corners.bottomRight = SprayState.corners.bottomRight + moveVec

    SprayState.rightAxis = norm(SprayState.corners.bottomRight - SprayState.corners.bottomLeft)
    SprayState.upAxis = norm(SprayState.corners.topLeft - SprayState.corners.bottomLeft)
end

-- ============================================================
-- UNDO / REDO
-- ============================================================

function PerformUndo()
    if #SprayState.strokeHistory == 0 then return end

    local stroke = table.remove(SprayState.strokeHistory)
    table.insert(SprayState.redoStack, stroke)

    SprayState.strokeCount = SprayState.strokeCount - 1
    SprayState.totalPoints = 0
    for _, s in ipairs(SprayState.strokeHistory) do
        SprayState.totalPoints = SprayState.totalPoints + #s.points
    end

    if SprayState.duiObject then
        SendDuiMessage(SprayState.duiObject, json.encode({ action = "undo" }))
    end

    SendNUIMessage({
        action = "undoRedo",
        canUndo = #SprayState.strokeHistory > 0,
        canRedo = #SprayState.redoStack > 0
    })
end

function PerformRedo()
    if #SprayState.redoStack == 0 then return end

    local stroke = table.remove(SprayState.redoStack)
    table.insert(SprayState.strokeHistory, stroke)

    SprayState.strokeCount = SprayState.strokeCount + 1
    SprayState.totalPoints = SprayState.totalPoints + #stroke.points

    if SprayState.duiObject then
        SendDuiMessage(SprayState.duiObject, json.encode({ action = "redo" }))
    end

    SendNUIMessage({
        action = "undoRedo",
        canUndo = #SprayState.strokeHistory > 0,
        canRedo = #SprayState.redoStack > 0
    })
end

-- ============================================================
-- PARTICLE & SOUND
-- ============================================================

function StartSprayParticle(color)
    if not Config.SprayParticle.enabled then return end
    StopSprayParticle()

    local dict = Config.SprayParticle.dict
    local name = Config.SprayParticle.name
    local scale = Config.SprayParticle.scale

    if not HasNamedPtfxAssetLoaded(dict) then return end
    if not SprayState.propEntity or not DoesEntityExist(SprayState.propEntity) then return end

    local r, g, b = 1.0, 1.0, 1.0
    if color and #color >= 7 then
        r = tonumber(color:sub(2, 3), 16) / 255.0
        g = tonumber(color:sub(4, 5), 16) / 255.0
        b = tonumber(color:sub(6, 7), 16) / 255.0
    end

    UseParticleFxAssetNextCall(dict)
    local handle = StartParticleFxLoopedOnEntity(name, SprayState.propEntity, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, scale, false, false, false)
    if handle > 0 then
        SetParticleFxLoopedColour(handle, r, g, b, 0)
        SetParticleFxLoopedAlpha(handle, 0.8)
        SprayState.ptfxHandle = handle
    end
end

function StopSprayParticle()
    if SprayState.ptfxHandle and SprayState.ptfxHandle > 0 then
        StopParticleFxLooped(SprayState.ptfxHandle, false)
        SprayState.ptfxHandle = nil
    end
end

function StartSpraySound()
    if Config.SpraySoundEnabled == false then return end
    SendNUIMessage({ action = "startSpraySound" })
end

function StopSpraySound()
    SendNUIMessage({ action = "stopSpraySound" })
end

-- ============================================================
-- NUI INTERACTION
-- ============================================================

SprayState._nuiMouseActive = false
function ToggleNuiMouse()
    if SprayState._nuiMouseActive then
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        SprayState._nuiMouseActive = false
    else
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(true)
        SprayState._nuiMouseActive = true
    end
end

function PaintingDistanceCheck()
    while SprayState.mode == "painting" or SprayState.mode == "erasing" do
        Wait(1000)
        if SprayState.corners then
            local pedCoords = GetEntityCoords(PlayerPedId())
            local center = SprayUtils.GetCenterFromCorners(SprayState.corners)
            local dist = #(pedCoords - center)

            if dist > Config.AutoSaveDistance then
                if SprayState.mode == "painting" then
                    Peak.Client.Notify(L("painting_auto_saved"), "info", Config.NotifyDuration)
                    ValidatePainting()
                elseif SprayState.mode == "erasing" then
                    FullCleanup()
                end
                return
            end
        end
    end
end

function StartLivePreviewLoop()
    CreateThread(function()
        while SprayState.mode == "painting" do
            Wait(Config.LivePreviewInterval or 1000)

            if SprayState.mode ~= "painting" then return end
            if SprayState.corners and SprayState.strokeHistory and #SprayState.strokeHistory > 0 then
                TriggerServerEvent(
                    "peak-sprays:sv:livePreview",
                    SprayState.strokeHistory,
                    SprayUtils.CornersToTable(SprayState.corners),
                    SprayState.canvasWidth or Config.CanvasWidth,
                    SprayState.canvasHeight or Config.CanvasHeight
                )
            end
        end
    end)
end

-- ============================================================
-- KEY MAPPINGS
-- ============================================================

RegisterCommand("+spray_shake", function()
    if SprayState.mode == "painting" and not SprayState._nuiMouseActive then
        PlayShakeAnimation()
    end
end, false)
RegisterKeyMapping("+spray_shake", "Spray Paint: Shake Can", "keyboard", "g")

RegisterCommand("+spray_undo", function()
    if SprayState.mode == "painting" and not SprayState._nuiMouseActive then
        PerformUndo()
    end
end, false)
RegisterKeyMapping("+spray_undo", "Spray Paint: Undo", "keyboard", "z")

RegisterCommand("+spray_redo", function()
    if SprayState.mode == "painting" and not SprayState._nuiMouseActive then
        PerformRedo()
    end
end, false)
RegisterKeyMapping("+spray_redo", "Spray Paint: Redo", "keyboard", "y")

RegisterCommand("+spray_validate", function()
    if SprayState._nuiMouseActive then return end
    if SprayState.mode == "painting" or SprayState.mode == "erasing" then
        SprayState.pendingValidate = true
    end
end, false)
RegisterKeyMapping("+spray_validate", "Spray Paint: Save / Validate", "keyboard", "RETURN")

RegisterCommand("+spray_cancel", function()
    if SprayState._nuiMouseActive then return end
    if SprayState.mode == "painting"
    or SprayState.mode == "erasing"
    or SprayState.mode == "selecting" then
        SprayState.pendingCancel = true
    end
end, false)
RegisterKeyMapping("+spray_cancel", "Spray Paint: Cancel", "keyboard", "DELETE")

RegisterCommand("+spray_cancel_alt", function()
    if SprayState._nuiMouseActive then return end
    if SprayState.mode == "painting"
    or SprayState.mode == "erasing"
    or SprayState.mode == "selecting" then
        SprayState.pendingCancel = true
    end
end, false)
RegisterKeyMapping("+spray_cancel_alt", "Spray Paint: Cancel (Backspace)", "keyboard", "BACK")

-- ============================================================
-- ANIMATIONS
-- ============================================================

function PlayShakeAnimation()
    local dict = Config.ShakeAnimation.dict
    local anim = Config.ShakeAnimation.anim
    local duration = Config.ShakeAnimation.duration

    Peak.Client.LoadAnimDict(dict)
    TaskPlayAnim(PlayerPedId(), dict, anim, 8.0, -8.0, duration, 49, 0, false, false, false)

    SetTimeout(duration + 200, function()
        if SprayState.mode == "painting" then
            local dictS = Config.SprayAnimation.dict
            local animS = Config.SprayAnimation.anim
            Peak.Client.LoadAnimDict(dictS)
            TaskPlayAnim(PlayerPedId(), dictS, animS, 8.0, -8.0, -1, Config.SprayAnimation.flag, 0, false, false, false)
        end
    end)
end
