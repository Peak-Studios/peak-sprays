Peak.Server.RegisterCallback("peak-sprays:isAdmin", function(source)
    return Peak.Server.IsAdmin(source)
end)

Peak.Server.RegisterCallback("peak-sprays:adminGetPaintings", function(source)
    if not Peak.Server.IsAdmin(source) then return {} end
    
    local result = Peak.Server.ExecuteSQL([[
        SELECT id, identifier, player_name, corners, normal, canvas_width, canvas_height,
        world_x, world_y, world_z, stroke_count, created_at, updated_at, expires_at
        FROM spray_paintings ORDER BY created_at DESC
    ]], {})
    
    if not result then return {} end
    
    local paintings = {}
    for _, row in ipairs(result) do
        table.insert(paintings, {
            id = row.id,
            identifier = row.identifier,
            playerName = row.player_name,
            corners = json.decode(row.corners),
            normal = json.decode(row.normal),
            canvasWidth = row.canvas_width,
            canvasHeight = row.canvas_height,
            worldX = row.world_x,
            worldY = row.world_y,
            worldZ = row.world_z,
            strokeCount = row.stroke_count,
            createdAt = row.created_at,
            updatedAt = row.updated_at,
            expiresAt = row.expires_at
        })
    end
    return paintings
end)

Peak.Server.RegisterCallback("peak-sprays:adminGetStrokeData", function(source, paintingId)
    if not Peak.Server.IsAdmin(source) then return nil end
    if not paintingId or type(paintingId) ~= "number" then return nil end

    local result = Peak.Server.ExecuteSQL("SELECT stroke_data FROM spray_paintings WHERE id = @id", {
        ["@id"] = paintingId
    })

    if not result or not result[1] or not result[1].stroke_data then return nil end
    return json.decode(result[1].stroke_data)
end)

Peak.Server.RegisterCallback("peak-sprays:adminDeletePainting", function(source, paintingId)
    if not Peak.Server.IsAdmin(source) then
        return { success = false, message = "No permission" }
    end
    
    if not paintingId or type(paintingId) ~= "number" then
        return { success = false, message = "Invalid painting ID" }
    end
    
    local info = Peak.Server.ExecuteSQL("SELECT id, identifier, player_name, world_x, world_y, world_z FROM spray_paintings WHERE id = @id", { ["@id"] = paintingId })
    
    local rowsAffected = Peak.Server.UpdateSQL("DELETE FROM spray_paintings WHERE id = @id", { ["@id"] = paintingId })
    if not rowsAffected or rowsAffected == 0 then
        return { success = false, message = "Painting not found or already deleted" }
    end
    
    TriggerClientEvent("peak-sprays:cl:removePainting", -1, paintingId)
    
    local adminName = Peak.Server.GetPlayerName(source)
    local adminIdentifier = Peak.Server.GetIdentifier(source)
    local creatorName = info and info[1] and info[1].player_name or "Unknown"
    
    LogAdminDelete(source, adminName, adminIdentifier, paintingId, creatorName)
    SprayUtils.DebugPrint("Admin", adminName, "deleted painting:", paintingId)
    
    return { success = true }
end)

Peak.Server.RegisterCallback("peak-sprays:adminUpdateExpiry", function(source, data)
    if not Peak.Server.IsAdmin(source) then
        return { success = false, message = "No permission" }
    end
    
    if not data or not data.id then
        return { success = false, message = "Invalid data" }
    end
    
    local expiryDate = nil
    if data.expiryDays and data.expiryDays > 0 then
        expiryDate = os.date("%Y-%m-%d %H:%M:%S", os.time() + (data.expiryDays * 86400))
    end
    
    local rowsAffected = Peak.Server.UpdateSQL("UPDATE spray_paintings SET expires_at = @expires_at WHERE id = @id", {
        ["@id"] = data.id,
        ["@expires_at"] = expiryDate
    })
    
    if not rowsAffected or rowsAffected == 0 then
        return { success = false, message = "Painting not found" }
    end
    
    return { success = true }
end)
