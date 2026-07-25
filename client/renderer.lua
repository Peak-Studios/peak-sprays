local ActiveRenderers = {}
local ActiveCount = 0

-- Slot allocation pool to reuse DUI and runtime TXD resources cleanly without memory leaks
local MaxSlots = Config.MaxActiveRenderers or 10
local FreeSlots = {}
for i = 1, MaxSlots do
    FreeSlots[#FreeSlots + 1] = i
end

local function AllocateSlot()
    if #FreeSlots > 0 then
        return table.remove(FreeSlots)
    end
    return nil
end

local function ReleaseSlot(slotId)
    if slotId then
        FreeSlots[#FreeSlots + 1] = slotId
    end
end

-- Pre-allocated table for distance sorting to prevent Lua GC spikes
local DistanceBuffer = {}

-- Renderer Management Loop
CreateThread(function()
    Wait(3000)
    while true do
        local pedCoords = GetEntityCoords(PlayerPedId())
        local count = 0
        
        for id, p in pairs(KnownPaintings) do
            count = count + 1
            local item = DistanceBuffer[count] or {}
            item.id = id
            item.dist = #(pedCoords - p.center)
            DistanceBuffer[count] = item
        end
        
        -- Clear remaining slots in buffer
        for i = count + 1, #DistanceBuffer do
            DistanceBuffer[i] = nil
        end
        
        table.sort(DistanceBuffer, function(a, b) return a.dist < b.dist end)
        
        local newActive = {}
        local currentActiveCount = 0
        
        for _, data in ipairs(DistanceBuffer) do
            local p = KnownPaintings[data.id]
            if p and p.renderState ~= "editing" then
                if data.dist < Config.RenderDistance and currentActiveCount < Config.MaxActiveRenderers then
                    newActive[data.id] = true
                    currentActiveCount = currentActiveCount + 1
                    
                    if p.renderState == "idle" then
                        p.renderState = "loading"
                        LoadAndCreateRenderer(p)
                    end
                elseif data.dist >= Config.UnloadDistance then
                    if p.renderState ~= "idle" then
                        UnloadRenderer(p)
                    end
                end
            end
        end
        
        -- Cleanup renderers no longer in top N
        for id, _ in pairs(ActiveRenderers) do
            if not newActive[id] then
                local p = KnownPaintings[id]
                if p then UnloadRenderer(p) end
            end
        end
        
        ActiveRenderers = newActive
        ActiveCount = currentActiveCount
        Wait(Config.RendererCheckInterval)
    end
end)

-- Main Rendering Loop
CreateThread(function()
    Wait(3000)
    while true do
        local sleep = 500
        local anyActive = false
        
        for id, _ in pairs(ActiveRenderers) do
            local p = KnownPaintings[id]
            if p and p.renderState == "active" and p.duiObj then
                anyActive = true
                break
            end
        end
        
        if anyActive then
            sleep = 0
            for id, _ in pairs(ActiveRenderers) do
                local p = KnownPaintings[id]
                if p and p.renderState == "active" and p.duiObj and p.txdName and p.txnName then
                    DrawPaintingSurface(p)
                end
            end
        end
        Wait(sleep)
    end
end)

function DrawPaintingSurface(p)
    local c = p.corners
    if not c then return end
    
    -- Two triangles for the quad
    DrawSpritePoly(
        c.topLeft.x, c.topLeft.y, c.topLeft.z,
        c.topRight.x, c.topRight.y, c.topRight.z,
        c.bottomRight.x, c.bottomRight.y, c.bottomRight.z,
        255, 255, 255, 255,
        p.txdName, p.txnName,
        0.0, 0.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0
    )
    DrawSpritePoly(
        c.topLeft.x, c.topLeft.y, c.topLeft.z,
        c.bottomRight.x, c.bottomRight.y, c.bottomRight.z,
        c.bottomLeft.x, c.bottomLeft.y, c.bottomLeft.z,
        255, 255, 255, 255,
        p.txdName, p.txnName,
        0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0
    )
end

function LoadAndCreateRenderer(p)
    p.renderGeneration = (p.renderGeneration or 0) + 1
    local generation = p.renderGeneration

    local slotId = AllocateSlot()
    if not slotId then
        p.renderState = "idle"
        return
    end

    p.slotId = slotId
    p.txdName = "peak_spray_slot_" .. slotId .. "_d"
    p.txnName = "peak_spray_slot_" .. slotId

    local strokeData = Peak.Client.TriggerCallback("peak-sprays:getStrokeData", p.id)
    if p.renderState ~= "loading" or p.renderGeneration ~= generation then
        ReleaseSlot(slotId)
        p.slotId = nil
        return
    end

    if not strokeData then
        p.renderState = "idle"
        ReleaseSlot(slotId)
        p.slotId = nil
        SprayUtils.DebugPrint("Failed to load stroke data for painting:", p.id)
        return
    end
    
    local w = p.canvasWidth or Config.CanvasWidth
    local h = p.canvasHeight or Config.CanvasHeight
    local url = ("nui://%s/ui/dist/canvas.html?width=%d&height=%d"):format(GetCurrentResourceName(), w, h)
    
    local duiObj = CreateDui(url, w, h)
    p.duiObj = duiObj
    
    CreateThread(function()
        local checks = 0
        while p.renderState == "loading" and p.renderGeneration == generation and p.duiObj == duiObj and checks < 50 do
            Wait(20)
            checks = checks + 1
            local handle = GetDuiHandle(duiObj)
            if handle and handle ~= "" then
                local txdHandle = CreateRuntimeTxd(p.txdName)
                CreateRuntimeTextureFromDuiHandle(txdHandle, p.txnName, handle)
                
                SendDuiMessage(duiObj, json.encode({
                    action = "init",
                    width = w,
                    height = h
                }))
                
                Wait(50)
                if p.renderState == "loading" and p.renderGeneration == generation and p.duiObj == duiObj then
                    SendDuiMessage(duiObj, json.encode({
                        action = "loadStrokes",
                        strokes = strokeData
                    }))
                    p.loaded = true
                    p.renderState = "active"
                    SprayUtils.DebugPrint("Renderer active for painting:", p.id)
                end
                return
            end
        end
        
        -- If loop timed out or state changed before loading succeeded
        if p.renderState == "loading" and p.renderGeneration == generation then
            UnloadRenderer(p)
        end
    end)
end

function UnloadRenderer(p)
    p.renderGeneration = (p.renderGeneration or 0) + 1

    if p.duiObj then
        DestroyDui(p.duiObj)
        p.duiObj = nil
    end

    if p.slotId then
        ReleaseSlot(p.slotId)
        p.slotId = nil
    end

    p.txdName = nil
    p.txnName = nil
    p.loaded = false
    p.renderState = "idle"
    ActiveRenderers[p.id] = nil
    SprayUtils.DebugPrint("Renderer unloaded for painting:", p.id)
end

function ForceReloadPainting(id)
    local p = KnownPaintings[id]
    if p then UnloadRenderer(p) end
end
_G.ForceReloadPainting = ForceReloadPainting

-- Live Preview System
local PreviewDui = nil
local PreviewTxd = nil
local PreviewTxn = nil
local PreviewCorners = nil
local IsPreviewing = false
local PreviewStartTime = 0
local PreviewCounter = 5000

function CleanupPreview()
    if PreviewDui then
        DestroyDui(PreviewDui)
        PreviewDui = nil
    end
    PreviewTxd = nil
    PreviewTxn = nil
    PreviewCorners = nil
    IsPreviewing = false
end

RegisterNetEvent("peak-sprays:cl:livePreview", function(sourcePlayer, payload)
    if sourcePlayer == GetPlayerServerId(PlayerId()) then return end
    if not Config.LivePreviewEnabled then return end
    if not payload or not payload.corners then return end
    
    local corners = SprayUtils.TableToCorners(payload.corners)
    if not corners then return end
    
    if not PreviewDui then
        PreviewCounter = PreviewCounter + 1
        PreviewTxd = "peak_spray_lp_" .. PreviewCounter .. "_d"
        PreviewTxn = "peak_spray_lp_" .. PreviewCounter
        
        local w = payload.width or Config.CanvasWidth
        local h = payload.height or Config.CanvasHeight
        local url = ("nui://%s/ui/dist/canvas.html?width=%d&height=%d"):format(GetCurrentResourceName(), w, h)
        
        PreviewDui = CreateDui(url, w, h)
        CreateRuntimeTxd(PreviewTxd)
        CreateRuntimeTextureFromDuiHandle(PreviewTxd, PreviewTxn, GetDuiHandle(PreviewDui))
        
        SetTimeout(500, function()
            if not PreviewDui then return end
            SendDuiMessage(PreviewDui, json.encode({
                action = "init",
                width = w,
                height = h
            }))
            SetTimeout(100, function()
                if not PreviewDui then return end
                if payload.newStrokes and #payload.newStrokes > 0 then
                    SendDuiMessage(PreviewDui, json.encode({ action = "loadStrokes", strokes = payload.newStrokes }))
                end
                if payload.activeStrokeUpdate then
                    SendDuiMessage(PreviewDui, json.encode({ action = "drawStroke", stroke = payload.activeStrokeUpdate }))
                end
                PreviewCorners = corners
                IsPreviewing = true
                PreviewStartTime = GetGameTimer()
            end)
        end)
    else
        -- Update existing preview
        if payload.newStrokes and #payload.newStrokes > 0 then
            SendDuiMessage(PreviewDui, json.encode({ action = "loadStrokes", strokes = payload.newStrokes, append = true }))
        end
        
        if payload.activeStrokeUpdate then
            -- Note: Our canvas JS needs to handle 'updateActivePreview' or similar
            SendDuiMessage(PreviewDui, json.encode({ 
                action = "updateActivePreview", 
                stroke = payload.activeStrokeUpdate 
            }))
        end
        
        PreviewCorners = corners
        IsPreviewing = true
        PreviewStartTime = GetGameTimer()
    end
end)

CreateThread(function()
    while true do
        if IsPreviewing and PreviewDui and PreviewCorners and PreviewTxd and PreviewTxn then
            if GetGameTimer() - PreviewStartTime > 10000 then
                CleanupPreview()
            else
                local c = PreviewCorners
                DrawSpritePoly(
                    c.topLeft.x, c.topLeft.y, c.topLeft.z,
                    c.topRight.x, c.topRight.y, c.topRight.z,
                    c.bottomRight.x, c.bottomRight.y, c.bottomRight.z,
                    255, 255, 255, 255,
                    PreviewTxd, PreviewTxn,
                    0.0, 0.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0
                )
                DrawSpritePoly(
                    c.topLeft.x, c.topLeft.y, c.topLeft.z,
                    c.bottomRight.x, c.bottomRight.y, c.bottomRight.z,
                    c.bottomLeft.x, c.bottomLeft.y, c.bottomLeft.z,
                    255, 255, 255, 255,
                    PreviewTxd, PreviewTxn,
                    0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0
                )
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    CleanupPreview()
end)
