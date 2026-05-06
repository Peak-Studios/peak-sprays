Peak = Peak or {}
Peak.Server = Peak.Server or {}

-- ============================================================
-- SQL HELPERS
-- ============================================================

--- Executes a SQL query and returns the result.
function Peak.Server.ExecuteSQL(query, params)
    local p = promise.new()
    MySQL.query(query, params or {}, function(res)
        p:resolve(res)
    end)
    return Citizen.Await(p)
end

--- Inserts a record into the database and returns the insert ID.
function Peak.Server.InsertSQL(query, params)
    local p = promise.new()
    MySQL.insert(query, params or {}, function(res)
        p:resolve(res)
    end)
    return Citizen.Await(p)
end

--- Updates records in the database and returns the number of rows affected.
function Peak.Server.UpdateSQL(query, params)
    local p = promise.new()
    MySQL.update(query, params or {}, function(res)
        p:resolve(res)
    end)
    return Citizen.Await(p)
end

-- ============================================================
-- INITIALIZATION & ITEM REGISTRATION
-- ============================================================

CreateThread(function()
    Wait(1000)
    if Config.UseItem then
        -- Generic spray paint
        Peak.Server.RegisterUsableItem(Config.SprayPaintItem, function(source, item)
            TriggerClientEvent("peak-sprays:useSprayPaint", source, item)
        end)
        
        -- Colored spray paints
        for itemName, color in pairs(Config.ColoredItems) do
            Peak.Server.RegisterUsableItem(itemName, function(source, item)
                TriggerClientEvent("peak-sprays:useSprayPaint", source, item)
            end)
        end
        
        -- Eraser cloth
        Peak.Server.RegisterUsableItem(Config.ClothItem, function(source, item)
            TriggerClientEvent("peak-sprays:useCloth", source)
        end)
    end
end)

-- ============================================================
-- CALLBACKS
-- ============================================================

Peak.Server.RegisterCallback("peak-sprays:hasSprayItem", function(source)
    if Peak.Server.HasItem(source, Config.SprayPaintItem, 1) then return true end
    for itemName, _ in pairs(Config.ColoredItems) do
        if Peak.Server.HasItem(source, itemName, 1) then return true end
    end
    return false
end)

Peak.Server.RegisterCallback("peak-sprays:hasClothItem", function(source)
    return Peak.Server.HasItem(source, Config.ClothItem, 1)
end)

Peak.Server.RegisterCallback("peak-sprays:getPaintings", function(source)
    local result = Peak.Server.ExecuteSQL("SELECT id, corners, normal, canvas_width, canvas_height, world_x, world_y, world_z, stroke_count FROM spray_paintings", {})
    if not result then return {} end
    
    local paintings = {}
    for _, row in ipairs(result) do
        table.insert(paintings, {
            id = row.id,
            corners = json.decode(row.corners),
            normal = json.decode(row.normal),
            canvas_width = row.canvas_width,
            canvas_height = row.canvas_height,
            world_x = row.world_x,
            world_y = row.world_y,
            world_z = row.world_z,
            stroke_count = row.stroke_count
        })
    end
    return paintings
end)

Peak.Server.RegisterCallback("peak-sprays:getStrokeData", function(source, paintingId)
    if not paintingId or type(paintingId) ~= "number" then return nil end

    local result = Peak.Server.ExecuteSQL("SELECT stroke_data FROM spray_paintings WHERE id = @id", {
        ["@id"] = paintingId
    })

    if not result or not result[1] or not result[1].stroke_data then return nil end
    return json.decode(result[1].stroke_data)
end)

Peak.Server.RegisterCallback("peak-sprays:savePainting", function(source, data)
    if not data or not data.corners or not data.normal or not data.strokeData then
        return { success = false, message = "Invalid data" }
    end
    
    if not ServerCanSpray(source) then return { success = false, message = "Permission denied" } end
    
    local identifier = Peak.Server.GetIdentifier(source)
    local playerName = Peak.Server.GetPlayerName(source)
    
    if Config.ConsumeSprayOnValidate then
        Peak.Server.RemoveItem(source, Config.SprayPaintItem, 1)
    end
    
    local expiryDate = nil
    if Config.ExpiryEnabled then
        expiryDate = os.date("%Y-%m-%d %H:%M:%S", os.time() + (Config.ExpiryDays * 86400))
    end
    
    local insertId = Peak.Server.InsertSQL([[
        INSERT INTO spray_paintings 
        (identifier, player_name, corners, normal, stroke_data, canvas_width, canvas_height, world_x, world_y, world_z, stroke_count, expires_at) 
        VALUES (@identifier, @player_name, @corners, @normal, @stroke_data, @canvas_width, @canvas_height, @world_x, @world_y, @world_z, @stroke_count, @expires_at)
    ]], {
        ["@identifier"] = identifier,
        ["@player_name"] = playerName,
        ["@corners"] = json.encode(data.corners),
        ["@normal"] = json.encode(data.normal),
        ["@stroke_data"] = json.encode(data.strokeData),
        ["@canvas_width"] = data.canvasWidth,
        ["@canvas_height"] = data.canvasHeight,
        ["@world_x"] = data.worldX,
        ["@world_y"] = data.worldY,
        ["@world_z"] = data.worldZ,
        ["@stroke_count"] = data.strokeCount,
        ["@expires_at"] = expiryDate
    })
    
    if not insertId or insertId == 0 then return { success = false, message = "DB Error" } end
    
    local clientData = {
        id = insertId,
        corners = data.corners,
        normal = data.normal,
        canvas_width = data.canvasWidth,
        canvas_height = data.canvasHeight,
        world_x = data.worldX,
        world_y = data.worldY,
        world_z = data.worldZ,
        stroke_count = data.strokeCount
    }
    
    TriggerClientEvent("peak-sprays:cl:newPainting", -1, clientData)
    LogPaintCreate(source, playerName, identifier, insertId, data)
    OnServerSprayCompleted(source, insertId, data)
    
    return { success = true, id = insertId }
end)

Peak.Server.RegisterCallback("peak-sprays:erasePainting", function(source, paintingId)
    if not ServerCanErase(source) then return { success = false, message = "Permission denied" } end
    
    local rows = Peak.Server.UpdateSQL("DELETE FROM spray_paintings WHERE id = @id", { ["@id"] = paintingId })
    if rows and rows > 0 then
        TriggerClientEvent("peak-sprays:cl:removePainting", -1, paintingId)
        local playerName = Peak.Server.GetPlayerName(source)
        local identifier = Peak.Server.GetIdentifier(source)
        LogPaintErase(source, playerName, identifier, paintingId)
        OnServerSprayRemoved(source, paintingId)
        return { success = true }
    end
    return { success = false, message = "Error or not found" }
end)

Peak.Server.RegisterCallback("peak-sprays:updatePainting", function(source, data)
    if not data or not data.paintingId or not data.strokeData then
        return { success = false, message = "Invalid data" }
    end

    if not ServerCanErase(source) then return { success = false, message = "Permission denied" } end

    local rows = Peak.Server.UpdateSQL([[
        UPDATE spray_paintings
        SET stroke_data = @stroke_data, stroke_count = @stroke_count
        WHERE id = @id
    ]], {
        ["@id"] = data.paintingId,
        ["@stroke_data"] = json.encode(data.strokeData),
        ["@stroke_count"] = data.strokeCount or #data.strokeData
    })

    if rows and rows > 0 then
        TriggerClientEvent("peak-sprays:cl:updatePainting", -1, {
            id = data.paintingId,
            stroke_count = data.strokeCount or #data.strokeData
        })

        local playerName = Peak.Server.GetPlayerName(source)
        local identifier = Peak.Server.GetIdentifier(source)
        LogPaintErase(source, playerName, identifier, data.paintingId)
        OnServerSprayRemoved(source, data.paintingId)
        return { success = true }
    end

    return { success = false, message = "Painting not found" }
end)

-- ============================================================
-- EXPIRY SYSTEM
-- ============================================================

if Config.ExpiryEnabled then
    CreateThread(function()
        while true do
            Wait(Config.ExpiryCheckInterval * 1000)
            local expired = Peak.Server.ExecuteSQL("SELECT id FROM spray_paintings WHERE expires_at IS NOT NULL AND expires_at < NOW()", {})
            if expired and #expired > 0 then
                for _, row in ipairs(expired) do
                    Peak.Server.UpdateSQL("DELETE FROM spray_paintings WHERE id = @id", { ["@id"] = row.id })
                    TriggerClientEvent("peak-sprays:cl:removePainting", -1, row.id)
                end
            end
        end
    end)
end

-- ============================================================
-- IMPORT / EXPORT
-- ============================================================

if Config.ImportExportEnabled then
    Peak.Server.RegisterCallback("peak-sprays:exportCurrentStrokes", function(source, data)
        local code = SprayUtils.GenerateExportCode(data.strokeData, data.canvasWidth, data.canvasHeight)
        return { success = true, code = code }
    end)
    
    Peak.Server.RegisterCallback("peak-sprays:importPainting", function(source, code)
        local strokeData, w, h = SprayUtils.DecodeExportCode(code)
        if not strokeData then return { success = false, message = "Invalid code" } end
        return { success = true, strokeData = strokeData, width = w, height = h }
    end)
end

-- ============================================================
-- LIVE PREVIEW
-- ============================================================

RegisterNetEvent("peak-sprays:sv:livePreview", function(strokeData, corners, width, height)
    local src = source
    if not Config.LivePreviewEnabled then return end
    TriggerClientEvent("peak-sprays:cl:livePreview", -1, src, strokeData, corners, width, height)
end)
