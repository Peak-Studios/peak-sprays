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
                onSelect = function() PreviewPainting(p.id) end
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
                        OpenAdminPanel()
                    end
                end
            }
        }
    })
    lib.showContext("spray_admin_actions")
end

function PreviewPainting(id)
    CleanupPreview()
    lib.notify({ title = "Loading preview...", type = "inform", duration = 2000 })
    
    local data = Peak.Client.TriggerCallback("peak-sprays:adminGetStrokeData", id)
    if not data or (type(data) == "table" and #data == 0) then
        lib.notify({ title = "Preview", description = "No stroke data found", type = "error" })
        return
    end
    
    local strokes = data.strokes or data
    previewCount = previewCount + 1
    
    local w = Config.CanvasWidth or 1024
    local h = Config.CanvasHeight or 1024
    local url = ("nui://%s/ui/dist/canvas.html"):format(GetCurrentResourceName())
    
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
