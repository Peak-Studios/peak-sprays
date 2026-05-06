function StartEraserMode()
    if not CanErase() then
        SprayUtils.DebugPrint("[Eraser] CanErase() returned false, blocking erase")
        return
    end
    
    SprayUtils.DebugPrint("[Eraser] Starting eraser mode")
    SprayState.mode = "erasing"
    SetFollowPedCamViewMode(4)
    Peak.Client.Notify(L("eraser_started"), "info", Config.NotifyDuration)
    
    CreateThread(EraserFindTarget)
end

function EraserFindTarget()
    local startTime = GetGameTimer()
    local timeout = 10000
    local found = false
    
    while SprayState.mode == "erasing" and not found do
        Wait(0)
        local ped = PlayerPedId()
        SetFollowPedCamViewMode(4)
        
        -- Disable standard firing controls
        DisableControlAction(0, 0, true) -- Next Camera
        DisableControlAction(0, 24, true) -- LMB
        DisableControlAction(0, 25, true) -- RMB
        
        local hit, hitCoords = RaycastModule.FromCamera(Config.EraserMaxDistance)
        if hit then
            RaycastModule.DrawCrosshair(hitCoords, 0, 200, 255)
            
            for id, p in pairs(KnownPaintings) do
                if p.corners then
                    local ok, u, v = RaycastModule.WorldToCanvas(hitCoords, p.corners, nil, nil)
                    if ok and u >= -0.05 and u <= 1.05 and v >= -0.05 and v <= 1.05 then
                        RaycastModule.DrawRectOutline(p.corners, 0, 200, 255, 200)
                        
                        if IsDisabledControlJustPressed(0, Config.Keys.EraseStroke) then
                            SprayState.paintingId = id
                            SprayState.targetPaintingCorners = p.corners
                            local right = norm(p.corners.bottomRight - p.corners.bottomLeft)
                            local up = norm(p.corners.topLeft - p.corners.bottomLeft)
                            SprayState.targetPaintingRight = right
                            SprayState.targetPaintingUp = up
                            SprayState.targetPaintingNormal = norm(cross(right, up))
                            found = true
                            break
                        end
                    end
                end
            end
        end
        
        if IsDisabledControlJustPressed(0, Config.Keys.CancelErase) then
            Peak.Client.Notify(L("eraser_cancelled"), "info", Config.NotifyDuration)
            FullCleanup()
            return
        end
        
        if GetGameTimer() - startTime > timeout then
            Peak.Client.Notify(L("no_painting_found"), "error", Config.NotifyDuration)
            FullCleanup()
            return
        end
    end
    
    if found then StartEraserSession() end
end

function StartEraserSession()
    local p = KnownPaintings[SprayState.paintingId]
    if not p then FullCleanup() return end
    
    SprayState.strokeCount = 0
    SprayState.totalPoints = 0
    SprayState.strokeHistory = {}
    SprayState.redoStack = {}
    SprayState.isDrawing = false
    SprayState.brushIndex = Config.DefaultBrushSizeIndex
    
    if p.renderState == "active" or p.renderState == "loading" then
        UnloadRenderer(p)
    end
    p.renderState = "editing"
    
    local timer = GetGameTimer()
    SprayState.duiTxd = "peak_spray_erase_" .. timer .. "_dict"
    SprayState.duiTxn = "peak_spray_erase_" .. timer
    
    local w = p.canvasWidth or Config.CanvasWidth
    local h = p.canvasHeight or Config.CanvasHeight
    local url = ("nui://%s/ui/dist/canvas.html?width=%d&height=%d"):format(GetCurrentResourceName(), w, h)
    
    local dui = CreateDui(url, w, h)
    SprayState.duiObject = dui
    
    SetTimeout(500, function()
        if not SprayState.duiObject then return end
        local txdHandle = CreateRuntimeTxd(SprayState.duiTxd)
        local handle = GetDuiHandle(dui)
        if handle and handle ~= "" then
            CreateRuntimeTextureFromDuiHandle(txdHandle, SprayState.duiTxn, handle)
        end
    end)
    
    local strokeData = Peak.Client.TriggerCallback("peak-sprays:getStrokeData", SprayState.paintingId)
    
    SetTimeout(400, function()
        if not SprayState.duiObject then return end
        SendDuiMessage(SprayState.duiObject, json.encode({ action = "init", width = w, height = h }))
        
        SetTimeout(100, function()
            if not SprayState.duiObject then return end
            if strokeData then
                SendDuiMessage(SprayState.duiObject, json.encode({ action = "loadStrokes", strokes = strokeData }))
                SprayState.existingStrokes = strokeData
            else
                SprayState.existingStrokes = {}
            end
            
            AttachClothProp()
            Peak.Client.LoadAnimDict(Config.EraseAnimation.dict)
            TaskPlayAnim(PlayerPedId(), Config.EraseAnimation.dict, Config.EraseAnimation.anim, 8.0, -8.0, -1, Config.EraseAnimation.flag, 0, false, false, false)
            
            SprayState.corners = SprayState.targetPaintingCorners
            SprayState.rightAxis = SprayState.targetPaintingRight
            SprayState.upAxis = SprayState.targetPaintingUp
            SprayState.surfaceNormal = SprayState.targetPaintingNormal
            
            SendNUIMessage({
                action = "openHUD",
                isEraseMode = true,
                brushSizes = Config.BrushSizes,
                currentBrushIndex = SprayState.brushIndex,
                pressure = 1.0,
                pressureEnabled = false,
                keys = {
                    size = "SCROLL",
                    erase = "LMB",
                    validate = "ENTER",
                    cancel = "DEL",
                    undo = "Z",
                    redo = "Y",
                    deleteAll = "X"
                }
            })
            
            CreateThread(EraserRenderLoop)
            CreateThread(EraserInputLoop)
            CreateThread(PaintingDistanceCheck)
        end)
    end)
end

function EraserRenderLoop()
    while SprayState.mode == "erasing" and SprayState.duiObject do
        Wait(0)
        local ped = PlayerPedId()
        local isErasing = IsDisabledControlPressed(0, Config.Keys.EraseStroke)
        
        local isPlaying = IsEntityPlayingAnim(ped, Config.EraseAnimation.dict, Config.EraseAnimation.anim, 3)
        if not isPlaying then
            TaskPlayAnim(ped, Config.EraseAnimation.dict, Config.EraseAnimation.anim, 8.0, -8.0, -1, Config.EraseAnimation.flag, 0, false, false, false)
            if not isErasing then SetEntityAnimSpeed(ped, Config.EraseAnimation.dict, Config.EraseAnimation.anim, 0.0) end
        elseif isErasing then
            SetEntityAnimSpeed(ped, Config.EraseAnimation.dict, Config.EraseAnimation.anim, 1.0)
        else
            SetEntityAnimSpeed(ped, Config.EraseAnimation.dict, Config.EraseAnimation.anim, 0.0)
            SetEntityAnimCurrentTime(ped, Config.EraseAnimation.dict, Config.EraseAnimation.anim, 0.0)
        end
        
        local corners = SprayState.corners
        if corners and SprayState.duiTxd then
            local hit, hitCoords = RaycastModule.FromCameraToPlane(SprayState.corners.bottomLeft, SprayState.surfaceNormal, Config.EraserMaxDistance)
            if hit then
                local brush = Config.BrushSizes[SprayState.brushIndex]
                local width = #(corners.bottomRight - corners.bottomLeft)
                local canvasScale = (brush.size * 1.5) / Config.CanvasWidth * width * 0.5
                if canvasScale < 0.01 then canvasScale = 0.01 end
                
                local right = norm(corners.bottomRight - corners.bottomLeft)
                local up = norm(corners.topLeft - corners.bottomLeft)
                
                -- Circle preview
                local segments = 24
                local step = (2.0 * math.pi) / segments
                for i = 0, segments - 1 do
                    local a1, a2 = i * step, (i + 1) * step
                    local p1 = hitCoords + right * (math.cos(a1) * canvasScale) + up * (math.sin(a1) * canvasScale)
                    local p2 = hitCoords + right * (math.cos(a2) * canvasScale) + up * (math.sin(a2) * canvasScale)
                    DrawLine(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, 0, 200, 255, 220)
                end
                
                -- Center Cross
                local dotSize = 0.005
                DrawLine(hitCoords.x - right.x * dotSize, hitCoords.y - right.y * dotSize, hitCoords.z - right.z * dotSize, hitCoords.x + right.x * dotSize, hitCoords.y + right.y * dotSize, hitCoords.z + right.z * dotSize, 0, 200, 255, 255)
                DrawLine(hitCoords.x - up.x * dotSize, hitCoords.y - up.y * dotSize, hitCoords.z - up.z * dotSize, hitCoords.x + up.x * dotSize, hitCoords.y + up.y * dotSize, hitCoords.z + up.z * dotSize, 0, 200, 255, 255)
            end
            
            -- Draw Surface
            DrawSpritePoly(corners.topLeft.x, corners.topLeft.y, corners.topLeft.z, corners.topRight.x, corners.topRight.y, corners.topRight.z, corners.bottomRight.x, corners.bottomRight.y, corners.bottomRight.z, 255, 255, 255, 255, SprayState.duiTxd, SprayState.duiTxn, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0)
            DrawSpritePoly(corners.topLeft.x, corners.topLeft.y, corners.topLeft.z, corners.bottomRight.x, corners.bottomRight.y, corners.bottomRight.z, corners.bottomLeft.x, corners.bottomLeft.y, corners.bottomLeft.z, 255, 255, 255, 255, SprayState.duiTxd, SprayState.duiTxn, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0)
            RaycastModule.DrawRectOutline(corners, 0, 150, 255, 200)
        end
    end
end

function EraserInputLoop()
    while SprayState.mode == "erasing" do
        Wait(0)
        local time = GetGameTimer()
        
        -- Disable controls
        for _, c in ipairs({0, 24, 25, 140, 141, 142, 257, 47, 58}) do DisableControlAction(0, c, true) end
        DisablePlayerFiring(PlayerPedId(), true)
        SetFollowPedCamViewMode(4)
        
        if IsDisabledControlPressed(0, Config.Keys.EraseStroke) then
            HandleCanvasEraseInput(time)
        else
            if SprayState.isDrawing then EndCurrentStroke() end
        end
        
        if IsDisabledControlJustPressed(0, Config.Keys.ScrollUp) then CycleBrushSize(1)
        elseif IsDisabledControlJustPressed(0, Config.Keys.ScrollDown) then CycleBrushSize(-1) end
        
        if IsControlJustPressed(0, 73) then -- X: Delete All
            if SprayState.duiObject then
                if SprayState.isDrawing then EndCurrentStroke() end
                SendDuiMessage(SprayState.duiObject, json.encode({ action = "clear" }))
                SprayState.strokeHistory = {}
                SprayState.redoStack = {}
                SprayState.strokeCount = 0
                SprayState.totalPoints = 0
                SprayState.existingStrokes = {}
                Peak.Client.Notify(L("eraser_cleared_all"), "info", Config.NotifyDuration)
            end
        end
        
        if IsDisabledControlJustPressed(0, Config.Keys.ValidateErase) then
            ValidateErase()
            return
        end
        
        if IsDisabledControlJustPressed(0, Config.Keys.CancelErase) then
            CancelErase()
            return
        end
    end
end

function HandleCanvasEraseInput(time)
    if time - SprayState.lastStrokeTime < Config.StrokeThrottleMs then return end
    SprayState.lastStrokeTime = time
    
    local hit, hitCoords = RaycastModule.FromCameraToPlane(SprayState.corners.bottomLeft, SprayState.surfaceNormal, Config.EraserMaxDistance)
    if not hit then
        if SprayState.isDrawing then EndCurrentStroke() end
        return
    end
    
    local ok, u, v = RaycastModule.WorldToCanvas(hitCoords, SprayState.corners, SprayState.rightAxis, SprayState.upAxis)
    if not ok then
        if SprayState.isDrawing then EndCurrentStroke() end
        return
    end
    
    local x = u * Config.CanvasWidth
    local y = (1.0 - v) * Config.CanvasHeight
    local brush = Config.BrushSizes[SprayState.brushIndex]
    
    if not SprayState.isDrawing then
        if SprayState.strokeCount >= Config.MaxStrokesPerPainting then
            Peak.Client.Notify(L("max_strokes_reached"), "warning", Config.NotifyDuration)
            return
        end
        
        SprayState.isDrawing = true
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
        local current = SprayState.strokeHistory[#SprayState.strokeHistory]
        if current then
            if SprayState.totalPoints >= Config.MaxTotalPoints then
                EndCurrentStroke()
                return
            end
            
            table.insert(current.points, { x = x, y = y })
            SprayState.totalPoints = SprayState.totalPoints + 1
            
            SendDuiMessage(SprayState.duiObject, json.encode({
                action = "addPoint",
                x = x,
                y = y
            }))
        end
    end
end

function ValidateErase()
    if SprayState.mode ~= "erasing" then return end
    SprayUtils.DebugPrint("[Eraser] Validating erase, painting ID:", SprayState.paintingId)
    
    SprayState.mode = "saving"
    if SprayState.isDrawing then EndCurrentStroke() end
    ClearPedTasks(PlayerPedId())
    
    local p = KnownPaintings[SprayState.paintingId]
    if p then p.renderState = "idle" end
    
    local allStrokes = SprayState.existingStrokes or {}
    for _, s in ipairs(SprayState.strokeHistory) do
        table.insert(allStrokes, s)
    end
    
    local data = {
        paintingId = SprayState.paintingId,
        strokeData = allStrokes,
        strokeCount = #allStrokes
    }
    
    local result = Peak.Client.TriggerCallback("peak-sprays:updatePainting", data)
    if result and result.success then
        Peak.Client.Notify(L("eraser_saved"), "success", Config.NotifyDuration)
        if OnSprayRemoved then OnSprayRemoved(SprayState.paintingId) end
    else
        Peak.Client.Notify(result and result.message or "Error saving", "error", Config.NotifyDuration)
    end
    
    FullCleanup()
end

function CancelErase()
    if SprayState.mode ~= "erasing" then return end
    SprayState.mode = "saving"
    if SprayState.isDrawing then EndCurrentStroke() end
    ClearPedTasks(PlayerPedId())
    
    Peak.Client.Notify(L("eraser_cancelled"), "info", Config.NotifyDuration)
    local p = KnownPaintings[SprayState.paintingId]
    if p then
        p.loaded = false
        p.renderState = "idle"
    end
    FullCleanup()
end
