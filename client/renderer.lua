local ActiveRenderers = {}
local ActiveCount = 0
local TxdCounter = 1000

-- Renderer Management Loop
CreateThread(function()
    Wait(3000)
    while true do
        local pedCoords = GetEntityCoords(PlayerPedId())
        local distances = {}
        
        for id, p in pairs(KnownPaintings) do
            table.insert(distances, { id = id, dist = #(pedCoords - p.center) })
        end
        
        table.sort(distances, function(a, b) return a.dist < b.dist end)
        
        local newActive = {}
        local currentActiveCount = 0
        
        for _, data in ipairs(distances) do
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

    local strokeData = Peak.Client.TriggerCallback("peak-sprays:getStrokeData", p.id)
    if p.renderState ~= "loading" or p.renderGeneration ~= generation then return end

    if not strokeData then
        p.renderState = "idle"
        SprayUtils.DebugPrint("Failed to load stroke data for painting:", p.id)
        return
    end
    
    TxdCounter = TxdCounter + 1
    p.txdName = "peak_spray_r_" .. p.id .. "_" .. TxdCounter .. "_d"
    p.txnName = "peak_spray_r_" .. p.id .. "_" .. TxdCounter
    
    local w = p.canvasWidth or Config.CanvasWidth
    local h = p.canvasHeight or Config.CanvasHeight
    local url = ("nui://%s/ui/dist/canvas.html?width=%d&height=%d"):format(GetCurrentResourceName(), w, h)
    
    p.duiObj = CreateDui(url, w, h)
    
    SetTimeout(500, function()
        if p.renderState ~= "loading" or p.renderGeneration ~= generation or not p.duiObj then return end
        local txdHandle = CreateRuntimeTxd(p.txdName)
        local handle = GetDuiHandle(p.duiObj)
        if handle and handle ~= "" then
            CreateRuntimeTextureFromDuiHandle(txdHandle, p.txnName, handle)
        end
    end)
    
    SetTimeout(400, function()
        if p.renderState ~= "loading" or p.renderGeneration ~= generation or not p.duiObj then return end
        SendDuiMessage(p.duiObj, json.encode({
            action = "init",
            width = w,
            height = h
        }))
        
        SetTimeout(100, function()
            if p.renderState ~= "loading" or p.renderGeneration ~= generation or not p.duiObj then return end
            SendDuiMessage(p.duiObj, json.encode({
                action = "loadStrokes",
                strokes = strokeData
            }))
            p.loaded = true
            p.renderState = "active"
            SprayUtils.DebugPrint("Renderer active for painting:", p.id)
        end)
    end)
end

function UnloadRenderer(p)
    p.renderGeneration = (p.renderGeneration or 0) + 1

    if p.duiObj then
        DestroyDui(p.duiObj)
        p.duiObj = nil
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

RegisterNetEvent("peak-sprays:cl:livePreview", function(sourcePlayer, strokes, cornersTable, width, height)
    if sourcePlayer == GetPlayerServerId(PlayerId()) then return end
    if not Config.LivePreviewEnabled then return end
    if not strokes or not cornersTable then return end
    
    local corners = SprayUtils.TableToCorners(cornersTable)
    if not corners then return end
    
    if not PreviewDui then
        PreviewCounter = PreviewCounter + 1
        PreviewTxd = "peak_spray_lp_" .. PreviewCounter .. "_d"
        PreviewTxn = "peak_spray_lp_" .. PreviewCounter
        
        local w = width or Config.CanvasWidth
        local h = height or Config.CanvasHeight
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
                SendDuiMessage(PreviewDui, json.encode({
                    action = "loadStrokes",
                    strokes = strokes
                }))
                PreviewCorners = corners
                IsPreviewing = true
                PreviewStartTime = GetGameTimer()
            end)
        end)
    else
        SendDuiMessage(PreviewDui, json.encode({ action = "clear" }))
        SetTimeout(50, function()
            if not PreviewDui then return end
            SendDuiMessage(PreviewDui, json.encode({
                action = "loadStrokes",
                strokes = strokes
            }))
            PreviewCorners = corners
            IsPreviewing = true
            PreviewStartTime = GetGameTimer()
        end)
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
