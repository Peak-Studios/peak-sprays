Peak = Peak or {}
Peak.Server = Peak.Server or {}
Peak.Server.TextScenes = {}

local function sqlDateFromHours(hours)
    if not hours or hours <= 0 then return nil end
    return os.date("%Y-%m-%d %H:%M:%S", os.time() + (hours * 3600))
end

local function tableHasValue(list, value)
    if not list or not value then return false end
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

local function normalizeDisplayData(data, isAdmin)
    if type(data) ~= "table" then return nil, "Invalid data" end

    local text = tostring(data.text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil, L("scene_invalid_text") end
    if #text > Config.SceneMaxTextLength then return nil, L("scene_text_too_long") end

    local font = tostring(data.font or "Oswald")
    if not tableHasValue(Config.SceneFonts, font) then font = "Oswald" end

    local background = tostring(data.background or "empty")
    if not tableHasValue(Config.SceneBackgrounds, background) then background = "empty" end

    local hoursVisible = tonumber(data.hoursVisible) or Config.SceneDefaultHours
    if Config.SceneAllowPermanentAdmin and isAdmin and hoursVisible <= 0 then
        hoursVisible = 0
    else
        hoursVisible = math.max(1, math.floor(hoursVisible))
    end

    local distance = SprayUtils.Clamp(tonumber(data.distance) or Config.SceneDefaultDistance, 2.0, 50.0)
    local closeDistance = SprayUtils.Clamp(tonumber(data.closeDistance) or Config.SceneDefaultCloseDistance, 1.0, distance)

    return {
        text = text,
        font = font,
        fontSize = SprayUtils.Clamp(tonumber(data.fontSize) or 48, 12, 128),
        fontColor = tostring(data.fontColor or "#ffffff"),
        fontOutline = tostring(data.fontOutline or "none"),
        fontOutlineColor = tostring(data.fontOutlineColor or "#000000"),
        fontStyle = tostring(data.fontStyle or "normal"),
        background = background,
        backgroundFill = tostring(data.backgroundFill or "contain"),
        backgroundOffsetX = SprayUtils.Clamp(tonumber(data.backgroundOffsetX) or 50, 0, 100),
        backgroundOffsetY = SprayUtils.Clamp(tonumber(data.backgroundOffsetY) or 50, 0, 100),
        backgroundSizeX = SprayUtils.Clamp(tonumber(data.backgroundSizeX) or 100, 10, 100),
        backgroundSizeY = SprayUtils.Clamp(tonumber(data.backgroundSizeY) or 100, 10, 100),
        backgroundColor = tostring(data.backgroundColor or "#262626"),
        rotationType = tostring(data.rotationType or "rotateGround"),
        distance = distance,
        closeDistance = closeDistance,
        hoursVisible = hoursVisible,
        visibility = tostring(data.visibility or "always")
    }
end

local function sceneFromRow(row)
    local displayData = Peak.Utils.JsonDecode(row.display_data) or {}
    local coords = Peak.Utils.JsonDecode(row.coords) or { x = 0.0, y = 0.0, z = 0.0 }
    local rotation = Peak.Utils.JsonDecode(row.rotation)

    return {
        id = row.id,
        identifier = row.identifier,
        playerName = row.player_name,
        sceneType = row.scene_type or "scene",
        displayData = displayData,
        coords = coords,
        rotation = rotation,
        isStaff = row.is_staff == 1 or row.is_staff == true,
        createdAt = row.created_at,
        expiresAt = row.expires_at
    }
end

local function broadcastDeleted(ids)
    TriggerClientEvent("peak-sprays:cl:deleteTextScenes", -1, ids)
end

local function bootstrapSceneTable()
    Peak.Server.ExecuteSQL([[
        CREATE TABLE IF NOT EXISTS peak_text_scenes (
            id INT(11) NOT NULL AUTO_INCREMENT,
            identifier VARCHAR(60) NOT NULL,
            player_name VARCHAR(100) DEFAULT 'Unknown',
            scene_type VARCHAR(20) NOT NULL DEFAULT 'scene',
            display_data LONGTEXT NOT NULL,
            coords JSON NOT NULL,
            rotation JSON DEFAULT NULL,
            is_staff TINYINT(1) NOT NULL DEFAULT 0,
            deleted TINYINT(1) NOT NULL DEFAULT 0,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            expires_at DATETIME DEFAULT NULL,
            PRIMARY KEY (id),
            INDEX idx_peak_text_scenes_identifier (identifier),
            INDEX idx_peak_text_scenes_deleted_expiry (deleted, expires_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]], {})
end

CreateThread(function()
    if not Config.ScenesEnabled then return end

    while not Peak.Server.Ready do Wait(250) end
    bootstrapSceneTable()

    local rows = Peak.Server.ExecuteSQL("SELECT * FROM peak_text_scenes WHERE deleted = 0 AND (expires_at IS NULL OR expires_at > NOW())", {})
    for _, row in ipairs(rows or {}) do
        local scene = sceneFromRow(row)
        Peak.Server.TextScenes[scene.id] = scene
    end

    if Config.SceneUseItem then
        Peak.Server.RegisterUsableItem(Config.SceneItem, function(source)
            TriggerClientEvent("peak-sprays:cl:openTextSceneCreator", source, "scene")
        end)

        Peak.Server.RegisterUsableItem(Config.SignItem, function(source)
            TriggerClientEvent("peak-sprays:cl:openTextSceneCreator", source, "sign")
        end)
    end
end)

CreateThread(function()
    if not Config.ScenesEnabled then return end

    while true do
        Wait((Config.SceneExpiryCheckInterval or 60) * 1000)
        local rows = Peak.Server.ExecuteSQL("SELECT id FROM peak_text_scenes WHERE deleted = 0 AND expires_at IS NOT NULL AND expires_at < NOW()", {})
        if rows and #rows > 0 then
            local ids = {}
            Peak.Server.UpdateSQL("UPDATE peak_text_scenes SET deleted = 1 WHERE deleted = 0 AND expires_at IS NOT NULL AND expires_at < NOW()", {})
            for _, row in ipairs(rows) do
                Peak.Server.TextScenes[row.id] = nil
                ids[#ids + 1] = row.id
            end
            broadcastDeleted(ids)
        end
    end
end)

Peak.Server.RegisterCallback("peak-sprays:getTextScenes", function()
    return Peak.Server.TextScenes
end)

Peak.Server.RegisterCallback("peak-sprays:getTextSceneHistory", function(source)
    local identifier = Peak.Server.GetIdentifier(source)
    if not identifier then return {} end

    local rows = Peak.Server.ExecuteSQL([[
        SELECT display_data, scene_type, created_at
        FROM peak_text_scenes
        WHERE identifier = @identifier AND deleted = 0
        ORDER BY id DESC
        LIMIT 5
    ]], { ["@identifier"] = identifier })

    local history = {}
    for _, row in ipairs(rows or {}) do
        local data = Peak.Utils.JsonDecode(row.display_data)
        if data then
            data.sceneType = row.scene_type
            data.createdAt = row.created_at
            history[#history + 1] = data
        end
    end
    return history
end)

Peak.Server.RegisterCallback("peak-sprays:createTextScene", function(source, payload)
    if not Config.ScenesEnabled then return { success = false, error = "Scenes disabled" } end
    if not payload or type(payload) ~= "table" then return { success = false, error = "Invalid data" } end
    if not ServerCanCreateScene(source, payload) then return { success = false, error = L("scene_no_permission") } end

    local coords = payload.coords
    if type(coords) ~= "table" or not coords.x or not coords.y or not coords.z then
        return { success = false, error = "Invalid coords" }
    end

    local isAdmin = Peak.Server.IsAdmin(source)
    local displayData, err = normalizeDisplayData(payload.displayData, isAdmin)
    if not displayData then return { success = false, error = err } end

    local sceneType = payload.sceneType == "sign" and "sign" or "scene"
    local rotation = payload.rotation
    local identifier = Peak.Server.GetIdentifier(source)
    local playerName = Peak.Server.GetPlayerName(source)
    if not identifier then return { success = false, error = "Missing player identifier" } end
    local expiresAt = sqlDateFromHours(displayData.hoursVisible)

    local insertId = Peak.Server.InsertSQL([[
        INSERT INTO peak_text_scenes
        (identifier, player_name, scene_type, display_data, coords, rotation, is_staff, expires_at)
        VALUES (@identifier, @player_name, @scene_type, @display_data, @coords, @rotation, @is_staff, @expires_at)
    ]], {
        ["@identifier"] = identifier,
        ["@player_name"] = playerName,
        ["@scene_type"] = sceneType,
        ["@display_data"] = Peak.Utils.JsonEncode(displayData),
        ["@coords"] = Peak.Utils.JsonEncode(coords),
        ["@rotation"] = rotation and Peak.Utils.JsonEncode(rotation) or nil,
        ["@is_staff"] = isAdmin and 1 or 0,
        ["@expires_at"] = expiresAt
    })

    if not insertId or insertId == 0 then
        return { success = false, error = "Database insert failed" }
    end

    if Config.SceneUseItem then
        if sceneType == "scene" and Config.SceneTextItemConsume then
            Peak.Server.RemoveItem(source, Config.SceneItem, 1)
        elseif sceneType == "sign" and Config.SceneSignItemConsume then
            Peak.Server.RemoveItem(source, Config.SignItem, 1)
        end
    end

    local scene = {
        id = insertId,
        identifier = identifier,
        playerName = playerName,
        sceneType = sceneType,
        displayData = displayData,
        coords = coords,
        rotation = rotation,
        isStaff = isAdmin,
        createdAt = os.date("%Y-%m-%d %H:%M:%S"),
        expiresAt = expiresAt
    }

    Peak.Server.TextScenes[insertId] = scene
    TriggerClientEvent("peak-sprays:cl:addTextScene", -1, scene)
    OnServerTextSceneCreated(source, insertId, scene)

    return { success = true, scene = scene }
end)

Peak.Server.RegisterCallback("peak-sprays:deleteTextScene", function(source, sceneId)
    sceneId = tonumber(sceneId)
    if not sceneId then return { success = false, error = "Invalid scene" } end

    local scene = Peak.Server.TextScenes[sceneId]
    if not scene then return { success = false, error = L("scene_not_found") } end

    local identifier = Peak.Server.GetIdentifier(source)
    local isOwner = identifier and scene.identifier == identifier
    local isAdmin = Peak.Server.IsAdmin(source)
    if not isOwner and not isAdmin and not ServerCanDeleteScene(source, scene) then
        return { success = false, error = L("scene_delete_denied") }
    end

    local rows = Peak.Server.UpdateSQL("UPDATE peak_text_scenes SET deleted = 1 WHERE id = @id", { ["@id"] = sceneId })
    if rows and rows > 0 then
        Peak.Server.TextScenes[sceneId] = nil
        broadcastDeleted({ sceneId })
        OnServerTextSceneDeleted(source, sceneId, scene)
        return { success = true }
    end

    return { success = false, error = "Delete failed" }
end)

Peak.Server.RegisterCallback("peak-sprays:adminGetTextScenes", function(source)
    if not Peak.Server.IsAdmin(source) then return {} end

    local rows = Peak.Server.ExecuteSQL("SELECT * FROM peak_text_scenes WHERE deleted = 0 ORDER BY created_at DESC", {})
    local scenes = {}
    for _, row in ipairs(rows or {}) do
        scenes[#scenes + 1] = sceneFromRow(row)
    end
    return scenes
end)

Peak.Server.RegisterCallback("peak-sprays:adminDeleteTextScene", function(source, sceneId)
    if not Peak.Server.IsAdmin(source) then
        return { success = false, error = L("admin_no_permission") }
    end
    return Peak.Server.Callbacks["peak-sprays:deleteTextScene"](source, sceneId)
end)
