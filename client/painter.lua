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
    SprayState.styleIndex = Config.DefaultPaintStyleIndex or 1
    SprayState.stencilIndex = 1
    SprayState.dwellTime = 0
    SprayState.lastPos = nil
    SprayState.lastDripTime = 0
    SprayState.pendingImage = nil

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

            if SprayState.activeItem == Config.GangSprayItem
            and Peak.ClientGang
            and Peak.ClientGang.gang
            and Peak.ClientGang.gang.official_mark then
                local mark = Peak.ClientGang.gang.official_mark
                local strokes = mark.strokeData or mark.strokes or mark
                if type(strokes) == "table" then
                    SprayState.strokeHistory = strokes
                    SprayState.strokeCount = #strokes
                    SendDuiMessage(SprayState.duiObject, json.encode({ action = "loadStrokes", strokes = strokes }))
                    SendNUIMessage({
                        action = "strokeUpdate",
                        strokeCount = SprayState.strokeCount,
                        maxStrokes = Config.MaxStrokesPerPainting,
                        canUndo = SprayState.strokeCount > 0,
                        canRedo = false
                    })
                end
            end
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
        imageSpraysEnabled = Config.ImageSpraysEnabled == true,
        imageDefaultSize = Config.ImageDefaultSize or 256,
        imageMinScale = Config.ImageMinScale or 0.25,
        imageMaxScale = Config.ImageMaxScale or 4.0,
        paintStyles = Config.PaintStyles,
        currentStyleIndex = SprayState.styleIndex,
        stencils = Config.Stencils,
        currentStencilIndex = SprayState.stencilIndex,
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
        if SprayState._nuiMouseActive then
            DisableSprayCameraLook()
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
                local style = Config.PaintStyles[SprayState.styleIndex] or Config.PaintStyles[Config.DefaultPaintStyleIndex or 1] or { id = "spray" }
                
                local visualSize = brush.size * spreadMult
                if style.id == 'pen' then visualSize = math.max(2.0, brush.size * 0.25) end

                -- Draw crosshair/brush preview
                local width = #(corners.bottomRight - corners.bottomLeft)
                local canvasScale = visualSize / (SprayState.canvasWidth or Config.CanvasWidth) * width * 0.5
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
            SetSprayMouseFocus(not SprayState._nuiMouseActive)
        end

        if SprayState._nuiMouseActive then
            DisableSprayCameraLook()
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
                SprayState.dwellTime = 0
                SprayState.lastPos = nil
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
            if SprayState.isDrawing then EndCurrentStroke() end
            SprayState.pendingValidate = false
            SprayState.pendingCancel = false
            ValidatePainting()
            return
        end

        if SprayState.pendingCancel then
            if SprayState.isDrawing then EndCurrentStroke() end
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
    if time - SprayState.lastStrokeTime < (Config.StrokeThrottleMs or 16) then return end
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
    local style = Config.PaintStyles[SprayState.styleIndex] or Config.PaintStyles[Config.DefaultPaintStyleIndex or 1] or { id = "spray" }
    local styleId = style.id or "spray"
    
    local size = math.floor(brush.size * spreadMult)
    local density = SprayState.density or 0.7
    local scatterCount = math.max(1, math.floor(brush.sprayDensity * spreadMult * density))
    local finalPressure = pressure
    local finalScatter = density

    -- Style overrides
    if styleId == 'pen' then
        size = math.max(2, math.floor((brush.size * 0.18) + 1))
        finalScatter = 0.0
        scatterCount = 1
    elseif styleId == 'calligraphy' then
        -- Varies size based on movement direction
        if SprayState.lastPos then
            local dx = x - SprayState.lastPos.x
            local dy = y - SprayState.lastPos.y
            local angle = math.abs(math.atan2(dy, dx))
            size = math.max(3, math.floor(size * (0.45 + 0.75 * math.abs(math.sin(angle + 0.8)))))
        end
        finalScatter = 0.0
        scatterCount = 1
    elseif styleId == 'splatter' then
        size = math.floor(size * 1.35)
        finalScatter = SprayUtils.Clamp(density * 1.35, 0.35, 1.35)
        scatterCount = math.max(4, math.floor(scatterCount * 0.8))
        finalPressure = pressure * (0.7 + 0.3 * math.random())
    elseif styleId == 'airbrush' then
        finalScatter = SprayUtils.Clamp(density * 1.6, 0.45, 1.6)
        finalPressure = pressure * 0.55
        scatterCount = math.max(3, math.floor(scatterCount * 0.9))
    elseif styleId == 'drip' then
        finalScatter = SprayUtils.Clamp(density * 0.22, 0.08, 0.28)
        scatterCount = math.max(2, math.floor(scatterCount * 0.22))
        -- Drip logic: check if dwelling
        local tolerance = Config.DripTolerance or 15.0
        if SprayState.lastPos and #(vec2(x, y) - SprayState.lastPos) < tolerance then
            SprayState.dwellTime = SprayState.dwellTime + (Config.StrokeThrottleMs or 16)
            local dripCooldown = math.max(650, math.floor((Config.DripThresholdMs or 400) * 1.8))
            if SprayState.dwellTime > (Config.DripThresholdMs or 400)
            and time - (SprayState.lastDripTime or 0) > dripCooldown then
                TriggerDrip(x, y, size, finalPressure)
                SprayState.lastDripTime = time
                SprayState.dwellTime = 0 -- Reset to allow next drip
            end
        else
            SprayState.dwellTime = 0
        end
        SprayState.lastPos = vec2(x, y)
    elseif styleId == 'stencil' then
        if IsDisabledControlJustPressed(0, 24) then
            TriggerStencil(x, y, size)
        end
        return -- Stencil handles its own stroke
    end

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
            style = styleId,
            color = SprayState.currentColor,
            size = size,
            density = scatterCount,
            pressure = finalPressure,
            scatter = finalScatter,
            points = {{ x = x, y = y }}
        }
        table.insert(SprayState.strokeHistory, newStroke)
        SprayState.activeStrokeIndex = #SprayState.strokeHistory
        SprayState.strokeCount = SprayState.strokeCount + 1

        SendDuiMessage(SprayState.duiObject, json.encode({
            action = "startStroke",
            type = "paint",
            style = styleId,
            x = x,
            y = y,
            color = SprayState.currentColor,
            size = size,
            density = scatterCount,
            pressure = finalPressure,
            scatter = finalScatter
        }))
        StartSpraySound()
        StartSprayParticle(SprayState.currentColor)
    else
        local currentStroke = SprayState.strokeHistory[SprayState.activeStrokeIndex or #SprayState.strokeHistory]
        if currentStroke then
            if #currentStroke.points >= (Config.MaxPointsPerStroke or 5000) then
                EndCurrentStroke()
                return
            end
            if SprayState.totalPoints >= (Config.MaxTotalPoints or 50000) then
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
                density = scatterCount,
                scatter = finalScatter
            }))
        end
    end
    
    if styleId ~= 'drip' then
        SprayState.lastPos = vec2(x, y)
    end
end

function TriggerDrip(startX, startY, size, pressure)
    if SprayState.strokeCount >= Config.MaxStrokesPerPainting then return end

    local canvasW = SprayState.canvasWidth or Config.CanvasWidth
    local canvasH = SprayState.canvasHeight or Config.CanvasHeight
    local dripSize = math.max(2, math.floor(math.min(size * 0.34, 7.0)))
    local bottomPadding = math.max(4, dripSize * 1.6)
    local availableLen = math.floor(canvasH - startY - bottomPadding)
    local minLen = math.max(10, math.floor(size * 0.75))
    if availableLen < minLen then return end

    local maxLen = math.min(Config.DripMaxLen or 180, math.floor(34 + size * 2.2), availableLen)
    if maxLen < minLen then return end

    local dripLen = math.random(minLen, maxLen)
    local dripPoints = {}
    local step = math.max(5, Config.DripSpeed or 5.0)
    local phase = math.random() * 6.28318
    local drift = (math.random() - 0.5) * math.min(5.0, size * 0.22)

    for i = 0, dripLen, step do
        local t = i / dripLen
        local wobble = math.sin(t * 6.0 + phase) * math.min(1.4, size * 0.06)
        local offsetX = drift * t + wobble + ((math.random() - 0.5) * 0.35)
        local px = SprayUtils.Clamp(startX + offsetX, dripSize, canvasW - dripSize)
        local py = SprayUtils.Clamp(startY + i, dripSize, canvasH - bottomPadding)
        table.insert(dripPoints, { x = px, y = py, t = t })
    end

    if dripPoints[#dripPoints] and dripPoints[#dripPoints].t < 1.0 then
        local px = SprayUtils.Clamp(startX + drift, dripSize, canvasW - dripSize)
        local py = SprayUtils.Clamp(startY + dripLen, dripSize, canvasH - bottomPadding)
        table.insert(dripPoints, { x = px, y = py, t = 1.0 })
    end

    if #dripPoints < 2 then return end
    if SprayState.totalPoints + #dripPoints > (Config.MaxTotalPoints or 50000) then return end
    
    local dripStroke = {
        type = "paint",
        style = "drip-run",
        color = SprayState.currentColor,
        size = dripSize,
        density = 1,
        pressure = pressure * 0.7,
        scatter = 0.0,
        points = dripPoints
    }
    
    table.insert(SprayState.strokeHistory, dripStroke)
    SprayState.strokeCount = SprayState.strokeCount + 1
    SprayState.totalPoints = SprayState.totalPoints + #dripPoints
    
    SendDuiMessage(SprayState.duiObject, json.encode({
        action = "drawStroke",
        stroke = dripStroke
    }))

    -- Update UI stroke count
    SendNUIMessage({
        action = "strokeUpdate",
        strokeCount = SprayState.strokeCount,
        maxStrokes = Config.MaxStrokesPerPainting,
        canUndo = true,
        canRedo = false
    })
end

function TriggerStencil(x, y, size)
    local stencil = Config.Stencils[SprayState.stencilIndex]
    if not stencil then return end
    
    if SprayState.strokeCount >= Config.MaxStrokesPerPainting then return end
    
    local stencilPoints = {}
    for _, p in ipairs(stencil.points) do
        table.insert(stencilPoints, { x = x + p.x * (size/10), y = y + p.y * (size/10) })
    end
    
    local stencilStroke = {
        type = "stencil",
        color = SprayState.currentColor,
        size = size,
        points = stencilPoints,
        pressure = 1.0
    }
    
    table.insert(SprayState.strokeHistory, stencilStroke)
    SprayState.strokeCount = SprayState.strokeCount + 1
    SprayState.totalPoints = SprayState.totalPoints + #stencilPoints
    
    SendDuiMessage(SprayState.duiObject, json.encode({
        action = "stampStencil",
        x = x,
        y = y,
        size = size,
        color = SprayState.currentColor,
        points = stencil.points
    }))
    
    SendNUIMessage({
        action = "strokeUpdate",
        strokeCount = SprayState.strokeCount,
        maxStrokes = Config.MaxStrokesPerPainting,
        canUndo = true,
        canRedo = false
    })
end

function HandleEraseInput(time)
    if time - SprayState.lastStrokeTime < (Config.StrokeThrottleMs or 16) then return end
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
            if SprayState.totalPoints >= (Config.MaxTotalPoints or 50000) then
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
    SprayState.activeStrokeIndex = nil

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

local function CountStrokePoints(stroke)
    if type(stroke) ~= "table" or type(stroke.points) ~= "table" then return 0 end
    return #stroke.points
end

local function UpdateStrokeHud()
    SendNUIMessage({
        action = "strokeUpdate",
        strokeCount = SprayState.strokeCount,
        maxStrokes = Config.MaxStrokesPerPainting,
        canUndo = #SprayState.strokeHistory > 0,
        canRedo = #SprayState.redoStack > 0
    })
end

local function ClampImageOperation(image)
    local canvasW = SprayState.canvasWidth or Config.CanvasWidth
    local canvasH = SprayState.canvasHeight or Config.CanvasHeight
    local defaultSize = Config.ImageDefaultSize or 256
    local minSize = defaultSize * (Config.ImageMinScale or 0.25)
    local maxSize = defaultSize * (Config.ImageMaxScale or 4.0)

    image.width = SprayUtils.Clamp(tonumber(image.width) or defaultSize, minSize, maxSize)
    image.height = SprayUtils.Clamp(tonumber(image.height) or image.width, minSize, maxSize)
    image.x = SprayUtils.Clamp(tonumber(image.x) or canvasW * 0.5, -canvasW, canvasW * 2)
    image.y = SprayUtils.Clamp(tonumber(image.y) or canvasH * 0.5, -canvasH, canvasH * 2)
    image.rotation = tonumber(image.rotation) or 0
    image.opacity = SprayUtils.Clamp(tonumber(image.opacity) or 1.0, 0.05, 1.0)
    image.flipX = image.flipX == true
    image.flipY = image.flipY == true
    return image
end

function AddImageToSpray(url)
    if Config.ImageSpraysEnabled ~= true then
        return { success = false, message = "Image sprays are disabled" }
    end
    if SprayState.mode ~= "painting" or not SprayState.duiObject then
        return { success = false, message = "You must be painting to add an image" }
    end
    if SprayState.pendingImage then
        return { success = false, message = "Finish the current image first" }
    end
    if SprayState.strokeCount >= Config.MaxStrokesPerPainting then
        return { success = false, message = L("max_strokes_reached") or "Max strokes reached" }
    end

    local imageCount = 0
    for _, stroke in ipairs(SprayState.strokeHistory) do
        if type(stroke) == "table" and stroke.type == "image" then imageCount = imageCount + 1 end
    end
    if imageCount >= (Config.ImageMaxPerSpray or 5) then
        return { success = false, message = "Too many images in this spray" }
    end

    local result = Peak.Client.TriggerCallback("peak-sprays:validateImageUrl", url)
    if not result or not result.success then
        return { success = false, message = result and result.message or "Invalid image URL" }
    end

    if SprayState.isDrawing then EndCurrentStroke() end
    SetSprayMouseFocus(true)

    local defaultSize = Config.ImageDefaultSize or 256
    local image = ClampImageOperation({
        type = "image",
        url = url,
        x = (SprayState.canvasWidth or Config.CanvasWidth) * 0.5,
        y = (SprayState.canvasHeight or Config.CanvasHeight) * 0.5,
        width = defaultSize,
        height = defaultSize,
        rotation = 0,
        opacity = 1.0,
        flipX = false,
        flipY = false
    })

    SprayState.pendingImage = image
    SendDuiMessage(SprayState.duiObject, json.encode({ action = "addImage", image = image }))
    SendNUIMessage({ action = "imageTransformUpdate", image = image })
    return { success = true, image = image }
end

function UpdatePendingImage(data)
    if SprayState.mode ~= "painting" or not SprayState.pendingImage then
        return { success = false, message = "No image is being edited" }
    end

    local image = SprayState.pendingImage
    if data.x ~= nil then image.x = tonumber(data.x) or image.x end
    if data.y ~= nil then image.y = tonumber(data.y) or image.y end
    if data.width ~= nil then image.width = tonumber(data.width) or image.width end
    if data.height ~= nil then image.height = tonumber(data.height) or image.height end
    if data.rotation ~= nil then image.rotation = tonumber(data.rotation) or image.rotation end
    if data.opacity ~= nil then image.opacity = tonumber(data.opacity) or image.opacity end
    if data.flipX ~= nil then image.flipX = data.flipX == true end
    if data.flipY ~= nil then image.flipY = data.flipY == true end

    ClampImageOperation(image)
    SendDuiMessage(SprayState.duiObject, json.encode({ action = "updateImage", image = image }))
    SendNUIMessage({ action = "imageTransformUpdate", image = image })
    return { success = true, image = image }
end

function CommitPendingImage()
    if SprayState.mode ~= "painting" or not SprayState.pendingImage then
        return { success = false, message = "No image is being edited" }
    end

    local image = ClampImageOperation(Peak.Utils.DeepCopy(SprayState.pendingImage))
    table.insert(SprayState.strokeHistory, image)
    SprayState.redoStack = {}
    SprayState.strokeCount = SprayState.strokeCount + 1
    SprayState.pendingImage = nil

    SendDuiMessage(SprayState.duiObject, json.encode({ action = "commitImage", image = image }))
    SendNUIMessage({ action = "imageTransformUpdate", image = nil })
    UpdateStrokeHud()
    return { success = true }
end

function CancelPendingImage()
    if SprayState.pendingImage and SprayState.duiObject then
        SendDuiMessage(SprayState.duiObject, json.encode({ action = "cancelImage" }))
    end
    SprayState.pendingImage = nil
    SendNUIMessage({ action = "imageTransformUpdate", image = nil })
    return { success = true }
end

-- ============================================================
-- ACTIONS
-- ============================================================

function ValidatePainting()
    if SprayState.mode ~= "painting" then return end

    if SprayState.isDrawing then EndCurrentStroke() end
    if SprayState.pendingImage then
        local committed = CommitPendingImage()
        if not committed or not committed.success then
            CancelPendingImage()
        end
    end
    if #SprayState.strokeHistory == 0 then
        CancelPainting()
        return
    end

    local center = SprayUtils.GetCenterFromCorners(SprayState.corners)
    local data = {
        corners = SprayUtils.CornersToTable(SprayState.corners),
        normal = SprayUtils.Vec3ToTable(SprayState.surfaceNormal),
        strokeData = SprayState.strokeHistory,
        canvasWidth = SprayState.canvasWidth or Config.CanvasWidth,
        canvasHeight = SprayState.canvasHeight or Config.CanvasHeight,
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
    CancelPendingImage()
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
        SprayState.totalPoints = SprayState.totalPoints + CountStrokePoints(s)
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
    SprayState.totalPoints = SprayState.totalPoints + CountStrokePoints(stroke)

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

function DisableSprayCameraLook()
    for _, control in ipairs({1, 2, 3, 4, 5, 6, 106}) do
        DisableControlAction(0, control, true)
    end
end

function SetSprayMouseFocus(active)
    active = active == true
    if SprayState._nuiMouseActive == active then return end

    SetNuiFocus(active, active)
    SetNuiFocusKeepInput(active)
    SprayState._nuiMouseActive = active

    if active and SprayState.isDrawing then
        EndCurrentStroke()
        SprayState._eraseMode = false
    end
end

function ToggleNuiMouse()
    SetSprayMouseFocus(not SprayState._nuiMouseActive)
end

function PaintingDistanceCheck()
    while SprayState.mode == "painting" or SprayState.mode == "erasing" do
        Wait(1000)
        if SprayState.corners then
            local pedCoords = GetEntityCoords(PlayerPedId())
            local center = SprayUtils.GetCenterFromCorners(SprayState.corners)
            local dist = #(pedCoords - center)

            if dist > (Config.AutoSaveDistance or 15.0) then
                if SprayState.mode == "painting" then
                    Peak.Client.Notify(L("painting_auto_saved"), "info", Config.NotifyDuration)
                    ValidatePainting()
                elseif SprayState.mode == "erasing" then
                    CancelErase(true)
                end
                return
            end
        end
    end
end

function StartLivePreviewLoop()
    CreateThread(function()
        local lastSyncedStrokeCount = 0
        local lastSyncedPointCount = 0
        
        while SprayState.mode == "painting" do
            Wait(Config.LivePreviewInterval or 1000)

            if SprayState.mode ~= "painting" then return end
            
            local history = SprayState.strokeHistory
            if not history or #history == 0 then
                lastSyncedStrokeCount = 0
                lastSyncedPointCount = 0
                goto continue
            end

            local activeIdx = SprayState.activeStrokeIndex
            local currentTotalStrokes = #history
            
            -- Prepare delta payload
            local payload = {
                type = "delta",
                newStrokes = {},
                activeStrokeUpdate = nil,
                corners = SprayUtils.CornersToTable(SprayState.corners),
                width = SprayState.canvasWidth or Config.CanvasWidth,
                height = SprayState.canvasHeight or Config.CanvasHeight
            }
            
            local shouldSync = false

            -- 1. Sync completed strokes (everything before the current active one)
            local completedLimit = activeIdx and (activeIdx - 1) or currentTotalStrokes
            if completedLimit > lastSyncedStrokeCount then
                for i = lastSyncedStrokeCount + 1, completedLimit do
                    table.insert(payload.newStrokes, history[i])
                end
                lastSyncedStrokeCount = completedLimit
                shouldSync = true
                -- Reset point sync when moving to a new stroke
                lastSyncedPointCount = 0 
            end

            -- 2. Sync the currently active stroke if it has new points
            if activeIdx and history[activeIdx] then
                local active = history[activeIdx]
                local currentPoints = #active.points
                
                if currentPoints > lastSyncedPointCount then
                    -- To ensure DUI accuracy, we send the stroke metadata + the NEW points
                    -- We'll send the full stroke for now but only if it's new/changed
                    -- Since it's only ONE stroke, it's very unlikely to hit 65KB
                    payload.activeStrokeUpdate = active
                    lastSyncedPointCount = currentPoints
                    shouldSync = true
                end
            end

            if shouldSync then
                TriggerServerEvent("peak-sprays:sv:livePreview", payload)
            end

            ::continue::
        end
    end)
end

-- ============================================================
-- NUI CALLBACKS
-- ============================================================

RegisterNUICallback('changeStyle', function(data, cb)
    if data.index then
        SprayState.styleIndex = data.index
        SprayUtils.DebugPrint("[Paint] Style changed to: " .. data.index)
    end
    cb('ok')
end)

RegisterNUICallback('changeStencil', function(data, cb)
    if data.index then
        SprayState.stencilIndex = data.index
        SprayUtils.DebugPrint("[Paint] Stencil changed to: " .. data.index)
    end
    cb('ok')
end)

RegisterNUICallback('addImageToSpray', function(data, cb)
    local result = AddImageToSpray(data and data.url)
    if not result or not result.success then
        Peak.Client.Notify(result and result.message or "Unable to add image", "error", Config.NotifyDuration)
    end
    cb(result)
end)

RegisterNUICallback('updateSprayImage', function(data, cb)
    cb(UpdatePendingImage(data or {}))
end)

RegisterNUICallback('commitSprayImage', function(_, cb)
    cb(CommitPendingImage())
end)

RegisterNUICallback('cancelSprayImage', function(_, cb)
    cb(CancelPendingImage())
end)

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
