local activePreviewDui = nil
local previewTxd = nil
local previewTxn = nil
local isPreviewing = false
local previewCount = 0

RegisterCommand(Config.AdminCommandName, function()
    local isAdmin = Peak.Client.TriggerCallback("peak-sprays:isAdmin")
    if not isAdmin then
        Peak.Client.Notify(L("admin_no_permission"), "error", Config.NotifyDuration)
        return
    end
    OpenAdminPanel()
end, false)

function OpenAdminPanel()
    lib.registerContext({
        id = "spray_admin_home",
        title = "Peak Sprays Admin",
        options = {
            {
                title = "Spray Paintings",
                description = "List, preview, teleport to, or delete freehand sprays",
                icon = "spray-can",
                onSelect = OpenPaintingAdminPanel
            },
            {
                title = "Text Scenes & Signs",
                description = "List, teleport to, or delete text scenes and signs",
                icon = "signs-post",
                onSelect = OpenTextSceneAdminPanel
            }
        }
    })
    lib.showContext("spray_admin_home")
end

function OpenPaintingAdminPanel()
    local paintings = Peak.Client.TriggerCallback("peak-sprays:adminGetPaintings")
    if not paintings or #paintings == 0 then
        lib.notify({ title = "Spray Admin", description = "No paintings found", type = "inform" })
        return
    end
    ShowPaintingList(paintings)
end

function ShowPaintingList(paintings)
    local options = {}
    for _, p in ipairs(paintings) do
        local coords = string.format("%.1f, %.1f, %.1f", p.worldX or 0, p.worldY or 0, p.worldZ or 0)
        local date = tostring(p.createdAt or "N/A")
        if #date > 16 then date = date:sub(1, 16) end
        
        local expiry = p.expiresAt and ("Expires: " .. tostring(p.expiresAt):sub(1, 10)) or "Permanent"
        
        table.insert(options, {
            title = "#" .. p.id .. "  " .. (p.playerName or "Unknown"),
            description = coords .. "  |  " .. (p.strokeCount or 0) .. " strokes  |  " .. date,
            metadata = {
                { label = "Player ID", value = p.identifier or "?" },
                { label = "Expiry", value = expiry }
            },
            icon = "spray-can",
            onSelect = function()
                ShowPaintingActions(p)
            end
        })
    end
    
    lib.registerContext({
        id = "spray_admin_list",
        title = "🎨 Spray Paint Admin  (" .. #paintings .. ")",
        menu = "spray_admin_home",
        options = options
    })
    lib.showContext("spray_admin_list")
end

function ShowPaintingActions(p)
    lib.registerContext({
        id = "spray_admin_actions",
        title = "Painting #" .. p.id .. "  —  " .. (p.playerName or "Unknown"),
        menu = "spray_admin_list",
        options = {
            {
                title = "👁️ Preview",
                description = "Render this painting in-game (DUI preview)",
                icon = "eye",
                onSelect = function() PreviewPainting(p) end
            },
            {
                title = "📍 Teleport",
                description = string.format("%.1f, %.1f, %.1f", p.worldX or 0, p.worldY or 0, p.worldZ or 0),
                icon = "location-dot",
                onSelect = function()
                    if p.worldX and p.worldY and p.worldZ then
                        SetEntityCoords(PlayerPedId(), p.worldX + 0.0, p.worldY + 0.0, p.worldZ + 0.0, false, false, false, true)
                        lib.notify({ title = "Teleported", description = "Painting #" .. p.id, type = "success" })
                    end
                end
            },
            {
                title = "🗑️ Delete",
                description = "Permanently delete this painting",
                icon = "trash",
                iconColor = "#ef4444",
                onSelect = function()
                    local confirm = lib.alertDialog({
                        header = "Delete Painting #" .. p.id .. "?",
                        content = "Created by **" .. (p.playerName or "Unknown") .. "**. This action cannot be undone.",
                        centered = true,
                        cancel = true
                    })
                    if confirm == "confirm" then
                        local result = Peak.Client.TriggerCallback("peak-sprays:adminDeletePainting", p.id)
                        if result and result.success then
                            lib.notify({ title = "Deleted", description = "Painting #" .. p.id .. " removed", type = "success" })
                        else
                            lib.notify({ title = "Error", description = result and result.message or "Delete failed", type = "error" })
                        end
                        Wait(200)
                        OpenPaintingAdminPanel()
                    end
                end
            }
        }
    })
    lib.showContext("spray_admin_actions")
end

function PreviewPainting(painting)
    CleanupPreview()
    lib.notify({ title = "Loading preview...", type = "inform", duration = 2000 })
    
    local id = type(painting) == "table" and painting.id or painting
    local data = Peak.Client.TriggerCallback("peak-sprays:adminGetStrokeData", id)
    if not data or (type(data) == "table" and #data == 0) then
        lib.notify({ title = "Preview", description = "No stroke data found", type = "error" })
        return
    end
    
    local strokes = data.strokes or data
    previewCount = previewCount + 1
    
    local w = (type(painting) == "table" and painting.canvasWidth) or Config.CanvasWidth or 1024
    local h = (type(painting) == "table" and painting.canvasHeight) or Config.CanvasHeight or 1024
    local url = ("nui://%s/ui/dist/canvas.html?width=%d&height=%d"):format(GetCurrentResourceName(), w, h)
    
    activePreviewDui = CreateDui(url, w, h)
    previewTxd = "peak_spray_admprev_" .. previewCount .. "_dict"
    previewTxn = "peak_spray_admprev_" .. previewCount
    
    local txd = CreateRuntimeTxd(previewTxd)
    CreateRuntimeTextureFromDuiHandle(txd, previewTxn, GetDuiHandle(activePreviewDui))
    
    Wait(600)
    if not activePreviewDui then return end
    SendDuiMessage(activePreviewDui, json.encode({ action = "init", width = w, height = h }))
    
    Wait(200)
    if not activePreviewDui then return end
    SendDuiMessage(activePreviewDui, json.encode({ action = "loadStrokes", strokes = strokes }))
    
    Wait(400)
    isPreviewing = true
    lib.notify({ title = "Preview", description = "Press BACKSPACE to close", type = "inform", duration = 3000 })
    
    CreateThread(function()
        while isPreviewing do
            Wait(0)
            DrawRect(0.5, 0.5, 1.0, 1.0, 0, 0, 0, 150)
            
            local ar = GetAspectRatio(false)
            local hSize = 0.55
            local wSize = hSize / ar
            
            DrawRect(0.5, 0.5, wSize + 0.01, hSize + 0.01, 255, 255, 255, 30)
            if previewTxd and previewTxn then
                DrawSprite(previewTxd, previewTxn, 0.5, 0.5, wSize, hSize, 0.0, 255, 255, 255, 255)
            end
            
            SetTextFont(4)
            SetTextScale(0.0, 0.35)
            SetTextColour(255, 255, 255, 200)
            SetTextCentre(true)
            SetTextEntry("STRING")
            AddTextComponentString("Painting #" .. id .. "  |  BACKSPACE to close")
            DrawText(0.5, 0.5 - (hSize * 0.5) - 0.035)
            
            DisableControlAction(0, 177, true) -- BACKSPACE
            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 200) then
                isPreviewing = false
            end
        end
        CleanupPreview()
    end)
end

function CleanupPreview()
    isPreviewing = false
    if activePreviewDui then
        DestroyDui(activePreviewDui)
        activePreviewDui = nil
    end
    previewTxd = nil
    previewTxn = nil
end

function OpenTextSceneAdminPanel()
    local scenes = Peak.Client.TriggerCallback("peak-sprays:adminGetTextScenes")
    if not scenes or #scenes == 0 then
        lib.notify({ title = "Text Scene Admin", description = "No text scenes found", type = "inform" })
        return
    end
    ShowTextSceneList(scenes)
end

function ShowTextSceneList(scenes)
    local options = {}
    for _, scene in ipairs(scenes) do
        local coords = scene.coords or {}
        local data = scene.displayData or {}
        local coordText = string.format("%.1f, %.1f, %.1f", coords.x or 0, coords.y or 0, coords.z or 0)
        local expiry = scene.expiresAt and ("Expires: " .. tostring(scene.expiresAt):sub(1, 16)) or "Permanent"

        options[#options + 1] = {
            title = "#" .. scene.id .. "  " .. (data.text or "Untitled"),
            description = coordText .. "  |  " .. (scene.sceneType or "scene") .. "  |  " .. expiry,
            metadata = {
                { label = "Creator", value = scene.playerName or "Unknown" },
                { label = "Identifier", value = scene.identifier or "?" },
                { label = "Visibility", value = data.visibility or "always" },
                { label = "Font", value = data.font or "?" }
            },
            icon = scene.sceneType == "sign" and "signs-post" or "message-square-text",
            onSelect = function()
                ShowTextSceneActions(scene)
            end
        }
    end

    lib.registerContext({
        id = "text_scene_admin_list",
        title = "Text Scenes & Signs (" .. #scenes .. ")",
        menu = "spray_admin_home",
        options = options
    })
    lib.showContext("text_scene_admin_list")
end

function ShowTextSceneActions(scene)
    local coords = scene.coords or {}
    local data = scene.displayData or {}

    lib.registerContext({
        id = "text_scene_admin_actions",
        title = "Scene #" .. scene.id,
        menu = "text_scene_admin_list",
        options = {
            {
                title = "Preview",
                description = "Render this scene/sign on screen",
                icon = "eye",
                onSelect = function()
                    PreviewTextScene(scene)
                end
            },
            {
                title = "Teleport",
                description = string.format("%.1f, %.1f, %.1f", coords.x or 0, coords.y or 0, coords.z or 0),
                icon = "location-dot",
                onSelect = function()
                    if coords.x and coords.y and coords.z then
                        SetEntityCoords(PlayerPedId(), coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, false, false, false, true)
                        lib.notify({ title = "Teleported", description = "Scene #" .. scene.id, type = "success" })
                    end
                end
            },
            {
                title = "Inspect",
                description = data.text or "Untitled",
                icon = "circle-info",
                metadata = {
                    { label = "Type", value = scene.sceneType or "scene" },
                    { label = "Background", value = data.background or "empty" },
                    { label = "Distance", value = tostring(data.distance or "?") },
                    { label = "Created", value = tostring(scene.createdAt or "?") }
                }
            },
            {
                title = "Delete",
                description = "Mark this text scene/sign deleted",
                icon = "trash",
                iconColor = "#ef4444",
                onSelect = function()
                    local confirm = lib.alertDialog({
                        header = "Delete Scene #" .. scene.id .. "?",
                        content = "Text: **" .. (data.text or "Untitled") .. "**",
                        centered = true,
                        cancel = true
                    })
                    if confirm == "confirm" then
                        local result = Peak.Client.TriggerCallback("peak-sprays:adminDeleteTextScene", scene.id)
                        if result and result.success then
                            lib.notify({ title = "Deleted", description = "Scene #" .. scene.id .. " removed", type = "success" })
                        else
                            lib.notify({ title = "Error", description = result and result.error or "Delete failed", type = "error" })
                        end
                        Wait(200)
                        OpenTextSceneAdminPanel()
                    end
                end
            }
        }
    })
    lib.showContext("text_scene_admin_actions")
end

function PreviewTextScene(scene)
    local renderer = Peak.SceneRenderers.GetRenderer(true)
    if not renderer then
        lib.notify({ title = "Preview", description = "No renderer available", type = "error" })
        return
    end

    Peak.SceneRenderers.Send(renderer, "setSceneData", scene.displayData or {})
    Peak.SceneRenderers.Send(renderer, "setEye", false)
    Peak.SceneRenderers.Send(renderer, "setVisible", true)

    Wait(250)
    local txd, txn = Peak.SceneRenderers.Texture(renderer)
    if not txd or not txn then
        Peak.SceneRenderers.DestroyRenderer(renderer)
        lib.notify({ title = "Preview", description = "Failed to load preview texture", type = "error" })
        return
    end

    lib.notify({ title = "Preview", description = "Press BACKSPACE to close", type = "inform", duration = 3000 })

    CreateThread(function()
        local previewing = true
        while previewing do
            Wait(0)
            DrawRect(0.5, 0.5, 1.0, 1.0, 0, 0, 0, 160)
            DrawRect(0.5, 0.5, 0.62, 0.37, 255, 255, 255, 24)
            DrawSprite(txd, txn, 0.5, 0.5, 0.58, 0.326, 0.0, 255, 255, 255, 255)

            DisableControlAction(0, 177, true)
            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 200) then
                previewing = false
            end
        end
        Peak.SceneRenderers.DestroyRenderer(renderer)
    end)
end
