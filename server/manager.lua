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

    local sourceType = stroke.sourceType or (stroke.data and "raster" or "url")
    if sourceType == "raster" then
        if type(stroke.data) ~= "string" or #stroke.data == 0 then
            return false, "Image raster data is required"
        end
        local maxBase64Len = (Config.MaxImageRasterBytes or 262144) * 4 / 3 + 64
        if #stroke.data > maxBase64Len then
            return false, "Image raster data exceeds 256KB limit"
        end
        local format = tostring(stroke.format or "png"):lower()
        if format ~= "png" and format ~= "jpeg" and format ~= "jpg" and format ~= "webp" then
            return false, "Unsupported image raster format: " .. format
        end
    else
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

--- Validates physical geometry and normal of a spray placement.
--- @param data table
--- @return boolean success, string|table result
function Peak.Server.ValidateGeometry(data)
    if not data or not data.corners or not data.normal then
        return false, "Missing corners or normal data"
    end

    local corners = data.corners
    local tl = corners.topLeft and vector3(tonumber(corners.topLeft.x) or 0, tonumber(corners.topLeft.y) or 0, tonumber(corners.topLeft.z) or 0)
    local tr = corners.topRight and vector3(tonumber(corners.topRight.x) or 0, tonumber(corners.topRight.y) or 0, tonumber(corners.topRight.z) or 0)
    local bl = corners.bottomLeft and vector3(tonumber(corners.bottomLeft.x) or 0, tonumber(corners.bottomLeft.y) or 0, tonumber(corners.bottomLeft.z) or 0)
    local br = corners.bottomRight and vector3(tonumber(corners.bottomRight.x) or 0, tonumber(corners.bottomRight.y) or 0, tonumber(corners.bottomRight.z) or 0)
    if not tl or not tr or not bl or not br then
        return false, "Malformed corners geometry"
    end

    -- Check coordinate finiteness
    for _, pt in ipairs({ tl, tr, bl, br }) do
        if pt.x ~= pt.x or pt.y ~= pt.y or pt.z ~= pt.z then
            return false, "Non-finite coordinates in corners"
        end
    end

    local normal = data.normal
    local normVec = normal and vector3(tonumber(normal.x) or 0, tonumber(normal.y) or 0, tonumber(normal.z) or 0)
    if not normVec or math.abs(#normVec - 1.0) > 0.15 then
        return false, "Invalid surface normal vector"
    end

    -- Check dimension bounds: span between 0.2m and 20m
    local wTop = #(tr - tl)
    local hLeft = #(tl - bl)
    if wTop < 0.2 or wTop > 20.0 or hLeft < 0.2 or hLeft > 20.0 then
        return false, "Corner geometry dimensions out of reasonable bounds"
    end

    return true, { tl = tl, tr = tr, bl = bl, br = br, normal = normVec }
end

local function ValidateEraseStrokes(strokes)
    if type(strokes) ~= "table" then return false, "Invalid erase strokes table" end
    if #strokes > 500 then return false, "Too many erase strokes (max 500)" end
    for i, s in ipairs(strokes) do
        if type(s) ~= "table" then return false, ("Erase stroke %d is not a table"):format(i) end
        local size = tonumber(s.size)
        if not size or size <= 0 or size > 300 then
            return false, ("Erase stroke %d has invalid size"):format(i)
        end
        local pts = s.points
        if type(pts) ~= "table" or #pts == 0 then
            return false, ("Erase stroke %d has no points"):format(i)
        end
        if #pts > 2000 then
            return false, ("Erase stroke %d exceeds max points limit"):format(i)
        end
        for _, pt in ipairs(pts) do
            if type(pt) ~= "table" or type(pt.x) ~= "number" or type(pt.y) ~= "number" then
                return false, "Invalid erase stroke point coordinates"
            end
        end
    end
    return true
end

--- Recursively validates untrusted document payload with strict bounding limits.
--- @param doc table
--- @param depth number|nil
--- @return boolean success, string|nil message
function Peak.Server.ValidateDocument(doc, depth)
    depth = depth or 1
    if depth > 5 then return false, "Document nesting too deep" end
    if type(doc) ~= "table" then return false, "Document must be a table" end

    -- Layered composition or normalized envelope
    if doc.documentType == "layered" or doc.isComposition == true or doc.composition ~= nil or doc.layers ~= nil then
        local comp = doc.composition or doc
        if Peak.Server.ValidatePaintingComposition then
            local ok, msg = Peak.Server.ValidatePaintingComposition(comp)
            if not ok then return false, msg end
        end
        local eraseMask = comp.eraseMask or doc.eraseMask
        if eraseMask and type(eraseMask) == "table" then
            local okErase, msgErase = ValidateEraseStrokes(eraseMask)
            if not okErase then return false, msgErase end
        end
        return true
    end

    -- Legacy stroke array
    local okImg, msgImg = ValidateImageOperations(doc)
    if not okImg then return false, msgImg end

    if doc.eraseMask and type(doc.eraseMask) == "table" then
        local okErase, msgErase = ValidateEraseStrokes(doc.eraseMask)
        if not okErase then return false, msgErase end
    end

    return true
end

local function ValidateIncomingPaintingData(strokeData)
    return Peak.Server.ValidateDocument(strokeData, 1)
end

--- Centralized mutation service for paintings (delete, expire, update).
--- Guarantees atomic DB operations and synchronization across in-memory caches and clients.
--- @param mutationType string "delete" | "expire" | "update"
--- @param paintingId number
--- @param payload table|nil { strokeData = table, strokeCount = number } for "update"
--- @param context table|nil { source = number, reason = string, admin = boolean, creatorName = string }
--- @return boolean success, string|nil message
function Peak.Server.MutatePainting(mutationType, paintingId, payload, context)
    context = context or {}
    paintingId = tonumber(paintingId)
    if not paintingId then return false, "Invalid painting ID" end

    if mutationType == "delete" or mutationType == "expire" then
        local rowsAffected = Peak.Server.UpdateSQL("DELETE FROM spray_paintings WHERE id = @id", {
            ["@id"] = paintingId
        })
        if not rowsAffected or rowsAffected == 0 then
            return false, "Painting not found or already deleted"
        end

        -- Evict from in-memory caches
        Peak.Server.KnownPaintingsCache[paintingId] = nil
        Peak.Server.StrokeDataCache[paintingId] = nil

        -- Broadcast deletion to all clients
        TriggerClientEvent("peak-sprays:cl:removePainting", -1, paintingId)

        -- Logging and lifecycle hooks
        if context.source and context.source > 0 then
            local playerName = Peak.Server.GetPlayerName(context.source)
            local identifier = Peak.Server.GetIdentifier(context.source)
            if context.admin then
                LogAdminDelete(context.source, playerName, identifier, paintingId, context.creatorName or "Unknown")
            else
                LogPaintErase(context.source, playerName, identifier, paintingId)
                OnServerSprayRemoved(context.source, paintingId)
            end
        else
            OnServerSprayRemoved(-1, paintingId)
        end

        return true
    elseif mutationType == "update" then
        if not payload or not payload.strokeData or not payload.strokeCount then
            return false, "Missing update payload"
        end

        local rows = Peak.Server.UpdateSQL([[
            UPDATE spray_paintings
            SET stroke_data = @stroke_data, stroke_count = @stroke_count
            WHERE id = @id
        ]], {
            ["@id"] = paintingId,
            ["@stroke_data"] = json.encode(payload.strokeData),
            ["@stroke_count"] = payload.strokeCount
        })

        if not rows or rows == 0 then
            return false, "Painting not found"
        end

        -- Update in-memory caches consistently
        if Peak.Server.KnownPaintingsCache[paintingId] then
            Peak.Server.KnownPaintingsCache[paintingId].stroke_count = payload.strokeCount
        end
        Peak.Server.StrokeDataCache[paintingId] = payload.strokeData

        TriggerClientEvent("peak-sprays:cl:updatePainting", -1, {
            id = paintingId,
            stroke_count = payload.strokeCount
        })

        if context.source and context.source > 0 then
            local playerName = Peak.Server.GetPlayerName(context.source)
            local identifier = Peak.Server.GetIdentifier(context.source)
            LogPaintErase(context.source, playerName, identifier, paintingId)
            OnServerSprayRemoved(context.source, paintingId)
        end

        return true
    end

    return false, "Unknown mutation type: " .. tostring(mutationType)
end

local PendingPublications = {}
local RecentRequestIds = {}

Peak.Server.RegisterCallback("peak-sprays:savePainting", function(source, data)
    if not data or not data.corners or not data.normal or not data.strokeData then
        return { success = false, message = "Invalid data" }
    end

    -- Idempotency Check: return cached result on duplicate requestId
    if data.requestId and RecentRequestIds[data.requestId] then
        return RecentRequestIds[data.requestId]
    end

    -- Serialization Lock: prevent concurrent publication race from same player
    if PendingPublications[source] then
        return { success = false, message = "A publication is already in progress" }
    end
    PendingPublications[source] = true

    local function DoPublish()
        -- Proximity Check
        local ped = GetPlayerPed(source)
        local pCoords = GetEntityCoords(ped)
        local worldPos = vector3(tonumber(data.worldX) or 0, tonumber(data.worldY) or 0, tonumber(data.worldZ) or 0)
        local maxDist = (Config.SelectionMaxDistance or 10.0) + 5.0
        if #(pCoords - worldPos) > maxDist then
            return { success = false, message = "Placement position is too far from player" }
        end

        -- Geometry verification
        local okGeom, geomRes = Peak.Server.ValidateGeometry(data)
        if not okGeom then
            return { success = false, message = geomRes }
        end

        -- Stroke / Composition validation
        local validArt, artMessage = ValidateIncomingPaintingData(data.strokeData)
        if not validArt then
            return { success = false, message = artMessage }
        end

        if not ServerCanSpray(source) then
            return { success = false, message = "Permission denied" }
        end

        -- Item Verification
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

        -- Reservation Pattern: Remove item first; compensate/refund if SQL fails
        local itemConsumed = false
        if Config.ConsumeSprayOnValidate then
            if Peak.Server.RemoveItem(source, itemToRemove, 1) then
                itemConsumed = true
            else
                return { success = false, message = "Failed to consume spray paint item" }
            end
        end

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

        if not insertId or insertId == 0 then
            -- Compensation / Refund
            if itemConsumed then
                Peak.Server.AddItem(source, itemToRemove, 1)
            end
            return { success = false, message = "Database error saving spray" }
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

        Peak.Server.KnownPaintingsCache[insertId] = clientData
        Peak.Server.StrokeDataCache[insertId] = normalizedDoc

        TriggerClientEvent("peak-sprays:cl:newPainting", -1, clientData)
        LogPaintCreate(source, playerName, identifier, insertId, data)
        OnServerSprayCompleted(source, insertId, data)
        if territory.gangId and Peak.Gangs and Peak.Gangs.AddSprayXp then
            Peak.Gangs.AddSprayXp(territory.gangId)
        end

        local response = { success = true, id = insertId }
        if data.requestId then
            RecentRequestIds[data.requestId] = response
            SetTimeout(60000, function()
                RecentRequestIds[data.requestId] = nil
            end)
        end

        return response
    end

    local ok, res = pcall(DoPublish)
    PendingPublications[source] = nil
    if not ok then
        SprayUtils.DebugPrint("Error in savePainting:", tostring(res))
        return { success = false, message = "Internal error during spray publication" }
    end
    return res
end)

Peak.Server.RegisterCallback("peak-sprays:erasePainting", function(source, paintingId)
    if not ServerCanErase(source) then return { success = false, message = "Permission denied" } end
    local ok, err = Peak.Server.MutatePainting("delete", paintingId, nil, { source = source, reason = "erased" })
    return { success = ok, message = err }
end)

--- Authoritative server cleaning endpoint.
--- Applies delta erase operations to server-owned eraseMask, or deletes painting on full clear.
--- Cleaners cannot alter or replace the underlying artwork layers.
local function HandleCleanPainting(source, data)
    if not data or not data.paintingId then
        return { success = false, message = "Invalid data: missing paintingId" }
    end

    local paintingId = tonumber(data.paintingId)
    local p = Peak.Server.KnownPaintingsCache[paintingId]
    if not p then
        return { success = false, message = "Painting not found" }
    end

    if not ServerCanErase(source) then
        return { success = false, message = "Permission denied" }
    end

    -- Proximity Check
    local ped = GetPlayerPed(source)
    local pCoords = GetEntityCoords(ped)
    local targetPos = p.world_x and vector3(p.world_x, p.world_y, p.world_z) or nil
    if not targetPos and p.corners and p.corners.bottomLeft then
        local bl = p.corners.bottomLeft
        local tr = p.corners.topRight
        targetPos = vector3((bl.x + tr.x) * 0.5, (bl.y + tr.y) * 0.5, (bl.z + tr.z) * 0.5)
    end

    local maxDist = (Config.EraserMaxDistance or 5.0) + 5.0
    if targetPos and #(pCoords - targetPos) > maxDist then
        return { success = false, message = "Too far from painting to clean" }
    end

    -- Verify cloth item on server
    if Config.ConsumeClothOnValidate then
        if not Peak.Server.HasItem(source, Config.ClothItem, 1) then
            return { success = false, message = "You do not have a cleaning cloth" }
        end
    end

    if data.isFullClean == true then
        -- Complete removal
        local ok, err = Peak.Server.MutatePainting("delete", paintingId, nil, { source = source, reason = "cleaned" })
        if ok then
            if Config.ConsumeClothOnValidate then
                Peak.Server.RemoveItem(source, Config.ClothItem, 1)
            end
            return { success = true, isDeleted = true }
        end
        return { success = false, message = err or "Failed to delete painting" }
    end

    -- Partial cleaning: append delta eraseStrokes
    local eraseStrokes = data.eraseStrokes
    if not eraseStrokes or #eraseStrokes == 0 then
        return { success = true, isDeleted = false, message = "No changes" }
    end

    local validErase, eraseErr = ValidateEraseStrokes(eraseStrokes)
    if not validErase then
        return { success = false, message = eraseErr }
    end

    local rawDoc = Peak.Server.StrokeDataCache[paintingId]
    if not rawDoc then
        local sqlRes = Peak.Server.ExecuteSQL("SELECT stroke_data FROM spray_paintings WHERE id = @id", { ["@id"] = paintingId })
        if sqlRes and sqlRes[1] and sqlRes[1].stroke_data then
            rawDoc = json.decode(sqlRes[1].stroke_data)
        end
    end

    if not rawDoc then
        return { success = false, message = "Painting stroke data not found" }
    end

    local doc = SprayUtils.NormalizePaintingDocument(rawDoc)
    doc.eraseMask = doc.eraseMask or {}
    for _, s in ipairs(eraseStrokes) do
        table.insert(doc.eraseMask, s)
    end

    local strokeCount = SprayUtils.CalculatePaintingStrokeCount(doc)
    local ok, err = Peak.Server.MutatePainting("update", paintingId, {
        strokeData = doc,
        strokeCount = strokeCount
    }, { source = source, reason = "cleaned" })

    if ok then
        if Config.ConsumeClothOnValidate then
            Peak.Server.RemoveItem(source, Config.ClothItem, 1)
        end
        return { success = true, isDeleted = false }
    end

    return { success = false, message = err or "Failed to update painting" }
end

Peak.Server.RegisterCallback("peak-sprays:cleanPainting", HandleCleanPainting)

--- Legacy update callback: routes through authoritative delta cleaning to prevent artwork tampering.
Peak.Server.RegisterCallback("peak-sprays:updatePainting", function(source, data)
    if not data or not data.paintingId then
        return { success = false, message = "Invalid data" }
    end

    -- Extract delta erase strokes from incoming data
    local eraseStrokes = {}
    if data.strokeData and type(data.strokeData) == "table" then
        if data.strokeData.eraseMask and type(data.strokeData.eraseMask) == "table" then
            eraseStrokes = data.strokeData.eraseMask
        elseif #data.strokeData > 0 then
            for _, s in ipairs(data.strokeData) do
                if type(s) == "table" and s.type == "erase" then
                    table.insert(eraseStrokes, s)
                end
            end
        end
    end

    return HandleCleanPainting(source, {
        paintingId = data.paintingId,
        isFullClean = false,
        eraseStrokes = eraseStrokes
    })
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
                    Peak.Server.MutatePainting("expire", row.id, nil, { reason = "expired" })
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
