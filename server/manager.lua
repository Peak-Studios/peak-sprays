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

        if Config.GangSprayItem and Config.GangSprayItem ~= Config.SprayPaintItem then
            Peak.Server.RegisterUsableItem(Config.GangSprayItem, function(source, item)
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

local function ExtractUrlHost(url)
    if type(url) ~= "string" then return nil end
    return url:match("^https://([^/%?#:]+)")
end

local function IsAllowedImageHost(host)
    if not host then return false end
    host = host:lower()

    for _, allowed in ipairs(Config.ImageAllowedHosts or {}) do
        allowed = tostring(allowed):lower()
        if host == allowed or host:sub(-(allowed:len() + 1)) == "." .. allowed then
            return true
        end
    end

    return false
end

local function ValidateImageOperation(stroke)
    if Config.ImageSpraysEnabled ~= true then
        return false, "Image sprays are disabled"
    end

    if type(stroke.url) ~= "string" or stroke.url == "" then
        return false, "Image URL is required"
    end

    if #stroke.url > (Config.ImageUrlMaxLength or 512) then
        return false, "Image URL is too long"
    end

    local host = ExtractUrlHost(stroke.url)
    if not host then
        return false, "Image URL must be HTTPS"
    end

    if not IsAllowedImageHost(host) then
        return false, "Image host is not allowed"
    end

    if type(stroke.x) ~= "number" or type(stroke.y) ~= "number"
    or type(stroke.width) ~= "number" or type(stroke.height) ~= "number" then
        return false, "Invalid image placement"
    end

    if stroke.flipX ~= nil and type(stroke.flipX) ~= "boolean" then
        return false, "Invalid image flip"
    end

    if stroke.flipY ~= nil and type(stroke.flipY) ~= "boolean" then
        return false, "Invalid image flip"
    end

    local defaultSize = Config.ImageDefaultSize or 256
    local minSize = defaultSize * (Config.ImageMinScale or 0.25)
    local maxSize = defaultSize * (Config.ImageMaxScale or 4.0)

    if stroke.width < minSize or stroke.height < minSize or stroke.width > maxSize or stroke.height > maxSize then
        return false, "Image size is outside allowed limits"
    end

    return true
end

local function ValidateImageOperations(strokeData)
    if type(strokeData) ~= "table" then
        return false, "Invalid stroke data"
    end

    local imageCount = 0
    for _, stroke in ipairs(strokeData) do
        if type(stroke) == "table" and stroke.type == "image" then
            imageCount = imageCount + 1
            if imageCount > (Config.ImageMaxPerSpray or 5) then
                return false, "Too many images in this spray"
            end

            local ok, message = ValidateImageOperation(stroke)
            if not ok then return false, message end
        end
    end

    return true
end

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

Peak.Server.RegisterCallback("peak-sprays:validateImageUrl", function(source, url)
    local defaultSize = Config.ImageDefaultSize or 256
    local ok, message = ValidateImageOperation({
        type = "image",
        url = url,
        x = defaultSize,
        y = defaultSize,
        width = defaultSize,
        height = defaultSize,
        rotation = 0,
        opacity = 1.0
    })

    return { success = ok, message = message }
end)

Peak.Server.KnownPaintingsCache = {}
Peak.Server.StrokeDataCache = {}
Peak.Server.PaintingsLoaded = false

CreateThread(function()
    Wait(1500)
    local result = Peak.Server.ExecuteSQL("SELECT id, corners, normal, stroke_data, canvas_width, canvas_height, world_x, world_y, world_z, stroke_count, gang_id, status FROM spray_paintings", {})
    if result then
        for _, row in ipairs(result) do
            local corners = json.decode(row.corners)
            local normal = json.decode(row.normal)
            local strokeData = json.decode(row.stroke_data)
            
            Peak.Server.KnownPaintingsCache[row.id] = {
                id = row.id,
                corners = corners,
                normal = normal,
                canvas_width = row.canvas_width,
                canvas_height = row.canvas_height,
                world_x = row.world_x,
                world_y = row.world_y,
                world_z = row.world_z,
                stroke_count = row.stroke_count,
                gang_id = row.gang_id,
                status = row.status
            }
            Peak.Server.StrokeDataCache[row.id] = strokeData
        end
    end
    Peak.Server.PaintingsLoaded = true
end)

Peak.Server.RegisterCallback("peak-sprays:getPaintings", function(source)
    while not Peak.Server.PaintingsLoaded do Wait(50) end
    local paintings = {}
    for _, p in pairs(Peak.Server.KnownPaintingsCache) do
        table.insert(paintings, p)
    end
    return paintings
end)

Peak.Server.RegisterCallback("peak-sprays:getStrokeData", function(source, paintingId)
    if not paintingId or type(paintingId) ~= "number" then return nil end
    return Peak.Server.StrokeDataCache[paintingId]
end)

local function ValidateIncomingPaintingData(strokeData)
    if type(strokeData) ~= "table" then
        return false, "Invalid stroke data"
    end

    -- If normalized document or layered composition
    if strokeData.documentType == "layered" or strokeData.isComposition == true or strokeData.composition ~= nil then
        local comp = strokeData.composition or strokeData
        if Peak.Server.ValidatePaintingComposition then
            local ok, msg = Peak.Server.ValidatePaintingComposition(comp)
            if not ok then return false, msg end
        end
        return true
    end

    -- If legacy stroke array
    return ValidateImageOperations(strokeData)
end

Peak.Server.RegisterCallback("peak-sprays:savePainting", function(source, data)
    if not data or not data.corners or not data.normal or not data.strokeData then
        return { success = false, message = "Invalid data" }
    end

    -- Proximity Check
    local ped = GetPlayerPed(source)
    local pCoords = GetEntityCoords(ped)
    local worldPos = vector3(tonumber(data.worldX) or 0, tonumber(data.worldY) or 0, tonumber(data.worldZ) or 0)
    local maxDist = (Config.SelectionMaxDistance or 10.0) + 5.0
    if #(pCoords - worldPos) > maxDist then
        return { success = false, message = "Placement position is too far from player" }
    end

    -- Geometry verification
    local corners = data.corners
    local tl = corners.topLeft and vector3(corners.topLeft.x or 0, corners.topLeft.y or 0, corners.topLeft.z or 0)
    local tr = corners.topRight and vector3(corners.topRight.x or 0, corners.topRight.y or 0, corners.topRight.z or 0)
    local bl = corners.bottomLeft and vector3(corners.bottomLeft.x or 0, corners.bottomLeft.y or 0, corners.bottomLeft.z or 0)
    local br = corners.bottomRight and vector3(corners.bottomRight.x or 0, corners.bottomRight.y or 0, corners.bottomRight.z or 0)
    if not tl or not tr or not bl or not br then
        return { success = false, message = "Malformed corners geometry" }
    end

    local normal = data.normal
    local normVec = normal and vector3(normal.x or 0, normal.y or 0, normal.z or 0)
    if not normVec or math.abs(#normVec - 1.0) > 0.15 then
        return { success = false, message = "Invalid surface normal vector" }
    end

    -- Stroke / Composition validation
    local validArt, artMessage = ValidateIncomingPaintingData(data.strokeData)
    if not validArt then
        return { success = false, message = artMessage }
    end
    
    if not ServerCanSpray(source) then return { success = false, message = "Permission denied" } end

    -- Verify item exists before proceeding
    local itemToRemove = (data.activeItem and Config.ColoredItems[data.activeItem]) and data.activeItem or Config.SprayPaintItem
    if Config.ConsumeSprayOnValidate then
        if not Peak.Server.HasItem(source, itemToRemove, 1) then
            return { success = false, message = "You do not have the required spray paint item" }
        end
    end

    local territory = Peak.Territory and Peak.Territory.ValidatePlacement(source, data) or { success = true, gangId = nil }
    if not territory or not territory.success then
        return territory or { success = false, message = "Territory validation failed" }
    end
    
    local identifier = Peak.Server.GetIdentifier(source)
    local playerName = Peak.Server.GetPlayerName(source)
    
    local expiryDate = nil
    if Config.ExpiryEnabled then
        expiryDate = os.date("%Y-%m-%d %H:%M:%S", os.time() + (Config.ExpiryDays * 86400))
    end

    local normalizedDoc = SprayUtils.NormalizePaintingDocument(data.strokeData)
    local strokeCount = SprayUtils.CalculatePaintingStrokeCount(normalizedDoc)
    
    local insertId = Peak.Server.InsertSQL([[
        INSERT INTO spray_paintings 
        (identifier, player_name, gang_id, status, corners, normal, stroke_data, canvas_width, canvas_height, world_x, world_y, world_z, stroke_count, expires_at) 
        VALUES (@identifier, @player_name, @gang_id, 'normal', @corners, @normal, @stroke_data, @canvas_width, @canvas_height, @world_x, @world_y, @world_z, @stroke_count, @expires_at)
    ]], {
        ["@identifier"] = identifier,
        ["@player_name"] = playerName,
        ["@gang_id"] = territory.gangId,
        ["@corners"] = json.encode(data.corners),
        ["@normal"] = json.encode(data.normal),
        ["@stroke_data"] = json.encode(normalizedDoc),
        ["@canvas_width"] = data.canvasWidth or 1024,
        ["@canvas_height"] = data.canvasHeight or 1024,
        ["@world_x"] = worldPos.x,
        ["@world_y"] = worldPos.y,
        ["@world_z"] = worldPos.z,
        ["@stroke_count"] = strokeCount,
        ["@expires_at"] = expiryDate
    })
    
    if not insertId or insertId == 0 then return { success = false, message = "DB Error" } end
    
    -- Consume item ONLY upon confirmed database insertion
    if Config.ConsumeSprayOnValidate then
        Peak.Server.RemoveItem(source, itemToRemove, 1)
    end

    local clientData = {
        id = insertId,
        corners = data.corners,
        normal = data.normal,
        canvas_width = data.canvasWidth or 1024,
        canvas_height = data.canvasHeight or 1024,
        world_x = worldPos.x,
        world_y = worldPos.y,
        world_z = worldPos.z,
        stroke_count = strokeCount,
        gang_id = territory.gangId,
        status = "normal"
    }
    
    -- Update in-memory caches consistently
    Peak.Server.KnownPaintingsCache[insertId] = clientData
    Peak.Server.StrokeDataCache[insertId] = normalizedDoc

    TriggerClientEvent("peak-sprays:cl:newPainting", -1, clientData)
    LogPaintCreate(source, playerName, identifier, insertId, data)
    OnServerSprayCompleted(source, insertId, data)
    if territory.gangId and Peak.Gangs and Peak.Gangs.AddSprayXp then
        Peak.Gangs.AddSprayXp(territory.gangId)
    end
    
    return { success = true, id = insertId }
end)

Peak.Server.RegisterCallback("peak-sprays:erasePainting", function(source, paintingId)
    if not ServerCanErase(source) then return { success = false, message = "Permission denied" } end
    
    local rows = Peak.Server.UpdateSQL("DELETE FROM spray_paintings WHERE id = @id", { ["@id"] = paintingId })
    if rows and rows > 0 then
        -- Evict from in-memory cache
        Peak.Server.KnownPaintingsCache[paintingId] = nil
        Peak.Server.StrokeDataCache[paintingId] = nil

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

    local validArt, artMessage = ValidateIncomingPaintingData(data.strokeData)
    if not validArt then
        return { success = false, message = artMessage }
    end

    if not ServerCanErase(source) then return { success = false, message = "Permission denied" } end

    -- Verify cloth item if consuming
    if data.consumedCloth and Config.ConsumeClothOnValidate then
        if not Peak.Server.HasItem(source, Config.ClothItem, 1) then
            return { success = false, message = "You do not have a cleaning cloth" }
        end
    end

    local normalizedDoc = SprayUtils.NormalizePaintingDocument(data.strokeData)
    local strokeCount = SprayUtils.CalculatePaintingStrokeCount(normalizedDoc)

    local rows = Peak.Server.UpdateSQL([[
        UPDATE spray_paintings
        SET stroke_data = @stroke_data, stroke_count = @stroke_count
        WHERE id = @id
    ]], {
        ["@id"] = data.paintingId,
        ["@stroke_data"] = json.encode(normalizedDoc),
        ["@stroke_count"] = strokeCount
    })

    if rows and rows > 0 then
        -- Consume cloth upon confirmed update
        if data.consumedCloth and Config.ConsumeClothOnValidate then
            Peak.Server.RemoveItem(source, Config.ClothItem, 1)
        end

        -- Update in-memory caches consistently
        if Peak.Server.KnownPaintingsCache[data.paintingId] then
            Peak.Server.KnownPaintingsCache[data.paintingId].stroke_count = strokeCount
        end
        Peak.Server.StrokeDataCache[data.paintingId] = normalizedDoc

        TriggerClientEvent("peak-sprays:cl:updatePainting", -1, {
            id = data.paintingId,
            stroke_count = strokeCount
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
        local validImages, imageMessage = ValidateImageOperations(data.strokeData)
        if not validImages then return { success = false, message = imageMessage } end

        local code = SprayUtils.GenerateExportCode(data.strokeData, data.canvasWidth, data.canvasHeight)
        return { success = true, code = code }
    end)
    
    Peak.Server.RegisterCallback("peak-sprays:importPainting", function(source, code)
        local strokeData, w, h = SprayUtils.DecodeExportCode(code)
        if not strokeData then return { success = false, message = "Invalid code" } end

        local validImages, imageMessage = ValidateImageOperations(strokeData)
        if not validImages then return { success = false, message = imageMessage } end

        return { success = true, strokeData = strokeData, width = w, height = h }
    end)
end

-- ============================================================
-- LIVE PREVIEW (ISOLATED & SCOPED)
-- ============================================================

local LastPreviewBroadcast = {}

RegisterNetEvent("peak-sprays:sv:livePreview", function(payload)
    local src = source
    if not Config.LivePreviewEnabled then return end
    if not payload or type(payload) ~= "table" then return end

    -- Rate limit: max 10 updates per second per client
    local now = GetGameTimer()
    if LastPreviewBroadcast[src] and (now - LastPreviewBroadcast[src]) < 100 then
        return
    end
    LastPreviewBroadcast[src] = now

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local srcBucket = GetEntityRoutingBucket(ped)
    local srcCoords = GetEntityCoords(ped)
    local maxDist = Config.LivePreviewDistance or 30.0

    local allPlayers = GetPlayers()
    for _, pid in ipairs(allPlayers) do
        local targetSrc = tonumber(pid)
        if targetSrc and targetSrc ~= src then
            local targetPed = GetPlayerPed(targetSrc)
            if targetPed and targetPed ~= 0 then
                local targetBucket = GetEntityRoutingBucket(targetPed)
                if targetBucket == srcBucket then
                    local targetCoords = GetEntityCoords(targetPed)
                    if #(srcCoords - targetCoords) <= maxDist then
                        TriggerClientEvent("peak-sprays:cl:livePreview", targetSrc, src, payload)
                    end
                end
            end
        end
    end
end)

AddEventHandler("playerDropped", function()
    local src = source
    LastPreviewBroadcast[src] = nil
    TriggerClientEvent("peak-sprays:cl:stopLivePreview", -1, src)
end)
