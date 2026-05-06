function LogPaintCreate(source, playerName, identifier, paintingId, data)
    if not Config.LogPaintCreate or ServerConfig.DiscordWebhook == "" then return end
    
    local location = string.format("%.1f, %.1f, %.1f", data.worldX, data.worldY, data.worldZ)
    local width, height = "~", "~"
    
    if data.corners and data.corners.topLeft and data.corners.topRight and data.corners.bottomLeft then
        local tl = data.corners.topLeft
        local tr = data.corners.topRight
        local bl = data.corners.bottomLeft
        
        -- Convert to vector3 if they are tables (common when coming from JSON/NUI)
        local vTL = type(tl) == "table" and vector3(tl.x, tl.y, tl.z) or tl
        local vTR = type(tr) == "table" and vector3(tr.x, tr.y, tr.z) or tr
        local vBL = type(bl) == "table" and vector3(bl.x, bl.y, bl.z) or bl
        
        width = string.format("%.2f", #(vTR - vTL))
        height = string.format("%.2f", #(vTL - vBL))
    end
    
    local strokeCount = data.strokeCount or (data.strokeData and #data.strokeData) or 0
    
    Peak.Server.SendDiscordWebhook(ServerConfig.DiscordWebhook, L("log_paint_created"), 
        string.format(L("log_paint_created_desc"), playerName, identifier), 
        Config.LogColors.Create, 
        {
            { name = L("log_field_painting_id"), value = tostring(paintingId), inline = true },
            { name = L("log_field_location"), value = location, inline = true },
            { name = L("log_field_strokes"), value = tostring(strokeCount), inline = true },
            { name = L("log_field_area_size"), value = width .. " x " .. height, inline = true }
        }, 
        "Peak Spray Paint | " .. os.date("%Y-%m-%d %H:%M:%S")
    )
end

function LogPaintErase(source, playerName, identifier, paintingId)
    if not Config.LogPaintErase or ServerConfig.DiscordWebhook == "" then return end
    
    Peak.Server.SendDiscordWebhook(ServerConfig.DiscordWebhook, L("log_paint_erased"), 
        string.format(L("log_paint_erased_desc"), playerName, identifier, tostring(paintingId)), 
        Config.LogColors.Erase, 
        {
            { name = L("log_field_painting_id"), value = tostring(paintingId), inline = true }
        }, 
        "Peak Spray Paint | " .. os.date("%Y-%m-%d %H:%M:%S")
    )
end

function LogPaintDelete(source, playerName, identifier, paintingId, creatorName)
    if not Config.LogPaintDelete or ServerConfig.DiscordWebhook == "" then return end
    
    Peak.Server.SendDiscordWebhook(ServerConfig.DiscordWebhook, L("log_paint_deleted"), 
        string.format(L("log_paint_deleted_desc"), playerName, identifier, tostring(paintingId)), 
        Config.LogColors.Delete, 
        {
            { name = L("log_field_painting_id"), value = tostring(paintingId), inline = true },
            { name = L("log_field_creator"), value = creatorName or "Unknown", inline = true }
        }, 
        "Peak Spray Paint | " .. os.date("%Y-%m-%d %H:%M:%S")
    )
end

function LogAdminDelete(source, adminName, adminIdentifier, paintingId, creatorName)
    if not Config.LogAdminActions or ServerConfig.DiscordWebhook == "" then return end
    
    Peak.Server.SendDiscordWebhook(ServerConfig.DiscordWebhook, L("log_admin_delete"), 
        string.format(L("log_admin_delete_desc"), adminName, adminIdentifier, tostring(paintingId)), 
        Config.LogColors.Admin, 
        {
            { name = L("log_field_painting_id"), value = tostring(paintingId), inline = true },
            { name = L("log_field_creator"), value = creatorName or "Unknown", inline = true }
        }, 
        "Peak Spray Paint | " .. os.date("%Y-%m-%d %H:%M:%S")
    )
end
