Peak = Peak or {}
Peak.Server = Peak.Server or {}

-- ============================================================
-- GANG HELPERS & CONFIGURABLE ADAPTERS
-- ============================================================

--- Returns player gang info { id = string, name = string, label = string, isBoss = boolean, grade = number }
function Peak.Server.GetPlayerGang(src)
    local fw = Peak.Server.FrameworkName
    local obj = Peak.Server.FrameworkObject
    local minBossGrade = Config.GangBossMinGrade or 3

    if fw == "qbcore" or fw == "qbox" then
        local player = obj.Functions.GetPlayer(src)
        if player and player.PlayerData and player.PlayerData.gang then
            local gang = player.PlayerData.gang
            local isBoss = gang.isboss == true or (gang.grade and (gang.grade.isboss == true or (gang.grade.level and gang.grade.level >= minBossGrade)))
            return {
                id = gang.name or "none",
                name = gang.name or "none",
                label = gang.label or gang.name or "None",
                isBoss = isBoss,
                grade = gang.grade and gang.grade.level or 0
            }
        end
    elseif fw == "esx" then
        local player = obj.GetPlayerFromId(src)
        if player then
            -- Check for job2 (common secondary gang job in ESX)
            local gangJob = player.getJob2 and player.getJob2()
            if gangJob and gangJob.name and gangJob.name ~= "unemployed" then
                local isBoss = (gangJob.grade_name and gangJob.grade_name:lower():find("boss") ~= nil) or (gangJob.grade and gangJob.grade >= minBossGrade)
                return {
                    id = gangJob.name,
                    name = gangJob.name,
                    label = gangJob.label or gangJob.name,
                    isBoss = isBoss,
                    grade = gangJob.grade or 0
                }
            end
            -- Check if primary job is in configured gang jobs
            local job = player.getJob()
            if job and job.name and job.name ~= "unemployed" then
                local isConfiguredGang = Config.ESXGangJobs and Config.ESXGangJobs[job.name] == true
                if isConfiguredGang then
                    local isBoss = (job.grade_name and job.grade_name:lower():find("boss") ~= nil) or (job.grade and job.grade >= minBossGrade)
                    return {
                        id = job.name,
                        name = job.name,
                        label = job.label or job.name,
                        isBoss = isBoss,
                        grade = job.grade or 0
                    }
                end
            end
        end
    end

    return { id = "none", name = "none", label = "None", isBoss = false, grade = 0 }
end

-- ============================================================
-- CENTRALIZED DESIGN POLICIES
-- ============================================================

--- Determines if a player can view/read a design record.
function Peak.Server.CanReadDesign(source, designRow)
    if not designRow then return false, "Design not found" end
    if designRow.is_server_template == 1 or designRow.category == "template" then
        return true
    end
    if Peak.Server.IsAdmin(source) then
        return true
    end
    local identifier = Peak.Server.GetIdentifier(source)
    if designRow.identifier == identifier then
        return true
    end
    if designRow.category == "gang" and designRow.gang_id and designRow.gang_id ~= "none" then
        local gang = Peak.Server.GetPlayerGang(source)
        if gang and gang.id == designRow.gang_id then
            return true
        end
    end
    return false, "Permission denied"
end

--- Determines if a player can modify/update an existing design row.
function Peak.Server.CanEditDesign(source, designRow)
    if not designRow then return false, "Design not found" end
    if designRow.is_server_template == 1 then
        if Peak.Server.IsAdmin(source) then return true end
        return false, "Cannot modify server templates"
    end
    if Peak.Server.IsAdmin(source) then return true end
    local identifier = Peak.Server.GetIdentifier(source)
    if designRow.identifier == identifier then
        return true
    end
    return false, "Permission denied"
end

--- Determines if a player can delete a design row.
function Peak.Server.CanDeleteDesign(source, designRow)
    return Peak.Server.CanEditDesign(source, designRow)
end

--- Determines if a player can publish an official crew/gang template.
function Peak.Server.CanPublishGangTemplate(source, targetGangId)
    local gang = Peak.Server.GetPlayerGang(source)
    if not gang or gang.id == "none" then
        return false, "You are not in a gang or crew"
    end
    if targetGangId and gang.id ~= targetGangId then
        return false, "Cannot publish for another gang"
    end
    if not gang.isBoss and not Peak.Server.IsAdmin(source) then
        return false, "Only gang leaders can publish official crew tags"
    end
    return true
end

-- ============================================================
-- BOUNDED RECURSIVE VALIDATION
-- ============================================================

local function ExtractUrlHost(url)
    if type(url) ~= "string" then return nil end
    return url:match("^https://([^/%?#:]+)")
end

local function IsPrivateAddress(host)
    if not host then return true end
    host = host:lower()
    if host == "localhost"
       or host:match("^127%.")
       or host:match("^10%.")
       or host:match("^192%.168%.")
       or host:match("^172%.(1[6-9]|2[0-9]|3[0-1])%.") then
        return true
    end
    return false
end

local function IsAllowedImageHost(host)
    if not host or IsPrivateAddress(host) then return false end
    host = host:lower()
    for _, allowed in ipairs(Config.ImageAllowedHosts or {}) do
        allowed = tostring(allowed):lower()
        if host == allowed or host:sub(-(allowed:len() + 1)) == "." .. allowed then
            return true
        end
    end
    return false
end

--- Recursively validates an untrusted composition document.
function Peak.Server.ValidatePaintingComposition(comp)
    if type(comp) ~= "table" then
        return false, "Composition must be an object"
    end

    local width = tonumber(comp.width) or 1024
    local height = tonumber(comp.height) or 1024
    if width < 256 or width > 2048 or height < 256 or height > 2048 then
        return false, "Canvas dimensions out of bounds (256 - 2048)"
    end
    if (width * height) > (2048 * 2048) then
        return false, "Total canvas pixel budget exceeded"
    end

    if comp.layers ~= nil and type(comp.layers) ~= "table" then
        return false, "Layers must be a table"
    end

    local layers = comp.layers or {}
    local maxLayers = Config.MaxLayersPerComposition or 32
    if #layers > maxLayers then
        return false, ("Layer count exceeds maximum of %d"):format(maxLayers)
    end

    local imageCount = 0
    local maxImages = Config.ImageMaxPerSpray or 5

    for i, layer in ipairs(layers) do
        if type(layer) ~= "table" then
            return false, ("Layer %d is invalid"):format(i)
        end

        local layerType = layer.type
        if layerType ~= "freehand" and layerType ~= "text" and layerType ~= "image" and layerType ~= "stencil" then
            return false, ("Layer %d has unknown type: %s"):format(i, tostring(layerType))
        end

        local opacity = tonumber(layer.opacity)
        if opacity == nil or opacity < 0.0 or opacity > 1.0 then
            return false, ("Layer %d has invalid opacity (must be 0.0 to 1.0)"):format(i)
        end

        if layerType == "text" then
            local text = layer.text
            if type(text) ~= "string" or #text > 200 then
                return false, ("Text layer %d exceeds 200 characters"):format(i)
            end
            local fontSize = tonumber(layer.fontSize)
            if fontSize == nil or fontSize <= 0 or fontSize > 300 then
                return false, ("Text layer %d has invalid font size"):format(i)
            end
            if type(layer.x) ~= "number" or type(layer.y) ~= "number" then
                return false, ("Text layer %d has invalid coordinates"):format(i)
            end
        elseif layerType == "image" then
            if Config.ImageSpraysEnabled ~= true then
                return false, "Image layers are disabled on this server"
            end
            imageCount = imageCount + 1
            if imageCount > maxImages then
                return false, ("Too many image layers (max %d)"):format(maxImages)
            end

            local sourceType = layer.sourceType or (layer.data and "raster" or "url")
            if sourceType == "raster" then
                local data = layer.data
                if type(data) ~= "string" or #data == 0 then
                    return false, ("Image layer %d raster payload is empty"):format(i)
                end
                local maxBase64Len = (Config.MaxImageRasterBytes or 262144) * 4 / 3 + 64
                if #data > maxBase64Len then
                    return false, ("Image layer %d raster payload exceeds 256KB limit"):format(i)
                end
                local format = tostring(layer.format or "png"):lower()
                if format ~= "png" and format ~= "jpeg" and format ~= "jpg" and format ~= "webp" then
                    return false, ("Image layer %d has unsupported raster format: %s"):format(i, format)
                end
            else
                local url = layer.url
                if type(url) ~= "string" or #url > (Config.ImageUrlMaxLength or 512) then
                    return false, ("Image layer %d URL invalid or too long"):format(i)
                end
                local host = ExtractUrlHost(url)
                if not host or not IsAllowedImageHost(host) then
                    return false, ("Image layer %d host is not permitted"):format(i)
                end
            end
        elseif layerType == "freehand" then
            local strokes = layer.strokes
            if strokes ~= nil and type(strokes) ~= "table" then
                return false, ("Freehand layer %d has invalid strokes"):format(i)
            end
            if strokes and #strokes > 100 then
                return false, ("Freehand layer %d exceeds 100 strokes limit"):format(i)
            end
        elseif layerType == "stencil" then
            if type(layer.stencilId) ~= "string" then
                return false, ("Stencil layer %d missing stencilId"):format(i)
            end
        end
    end

    return true
end

-- ============================================================
-- DEFAULT SERVER TEMPLATES
-- ============================================================

local DefaultServerTemplates = {
    {
        title = "Street Rebel Tag",
        category = "template",
        is_server_template = 1,
        variant = "default",
        composition = json.encode({
            version = "1.0.0",
            title = "Street Rebel Tag",
            width = 1024,
            height = 1024,
            background = "transparent",
            layers = {
                {
                    id = "layer_spray_bg",
                    name = "Splatter Glow",
                    type = "freehand",
                    visible = true,
                    locked = false,
                    opacity = 0.85,
                    brushStyle = "splatter",
                    strokes = {
                        {
                            type = "paint",
                            style = "splatter",
                            color = "#D6FF62",
                            size = 45,
                            density = 40,
                            pressure = 0.8,
                            scatter = 1.2,
                            points = {
                                { x = 320, y = 480 }, { x = 450, y = 500 }, { x = 600, y = 490 }, { x = 720, y = 520 }
                            }
                        }
                    }
                },
                {
                    id = "layer_text_main",
                    name = "Main Tag",
                    type = "text",
                    visible = true,
                    locked = false,
                    text = "PEAK REBEL",
                    font = "Rock Salt",
                    fontSize = 82,
                    fontWeight = "bold",
                    letterSpacing = 4,
                    lineHeight = 1.1,
                    color = "#FFFFFF",
                    x = 512,
                    y = 500,
                    rotation = -6,
                    scale = 1.0,
                    opacity = 1.0,
                    outline = { enabled = true, color = "#0A0A0A", width = 8 },
                    shadow = { enabled = true, color = "#000000", blur = 14, offsetX = 6, offsetY = 6 },
                    glow = { enabled = true, color = "#D6FF62", blur = 20 },
                    drip = { enabled = true, count = 4, length = 60, width = 4 },
                    spray = { enabled = true, count = 18, spread = 24 },
                    distress = { enabled = true, roughness = 0.25 }
                },
                {
                    id = "layer_stencil_star",
                    name = "Star Stamp",
                    type = "stencil",
                    visible = true,
                    locked = false,
                    stencilId = "Star",
                    x = 760,
                    y = 390,
                    size = 36,
                    rotation = 15,
                    color = "#D6FF62",
                    opacity = 0.95
                }
            }
        })
    },
    {
        title = "Crown Royalty",
        category = "template",
        is_server_template = 1,
        variant = "default",
        composition = json.encode({
            version = "1.0.0",
            title = "Crown Royalty",
            width = 1024,
            height = 1024,
            background = "transparent",
            layers = {
                {
                    id = "layer_crown",
                    name = "Gold Crown",
                    type = "stencil",
                    visible = true,
                    locked = false,
                    stencilId = "Crown",
                    x = 512,
                    y = 340,
                    size = 75,
                    rotation = 0,
                    color = "#FFD700",
                    opacity = 1.0
                },
                {
                    id = "layer_king_text",
                    name = "King Script",
                    type = "text",
                    visible = true,
                    locked = false,
                    text = "KINGS OF LS",
                    font = "Nosifer",
                    fontSize = 76,
                    fontWeight = "bold",
                    letterSpacing = 2,
                    lineHeight = 1.1,
                    color = "#E11D48",
                    x = 512,
                    y = 560,
                    rotation = 0,
                    scale = 1.0,
                    opacity = 1.0,
                    outline = { enabled = true, color = "#111827", width = 6 },
                    shadow = { enabled = true, color = "#000000", blur = 12, offsetX = 4, offsetY = 6 },
                    glow = { enabled = true, color = "#FB7185", blur = 18 },
                    drip = { enabled = true, count = 6, length = 75, width = 5 },
                    spray = { enabled = true, count = 12, spread = 20 },
                    distress = { enabled = false, roughness = 0 }
                }
            }
        })
    },
    {
        title = "Underground Skull",
        category = "template",
        is_server_template = 1,
        variant = "default",
        composition = json.encode({
            version = "1.0.0",
            title = "Underground Skull",
            width = 1024,
            height = 1024,
            background = "transparent",
            layers = {
                {
                    id = "layer_skull",
                    name = "Skull Mark",
                    type = "stencil",
                    visible = true,
                    locked = false,
                    stencilId = "Skull",
                    x = 512,
                    y = 420,
                    size = 90,
                    rotation = 0,
                    color = "#F43F5E",
                    opacity = 1.0
                },
                {
                    id = "layer_sub_text",
                    name = "Subtext",
                    type = "text",
                    visible = true,
                    locked = false,
                    text = "NO TRESPASSING",
                    font = "Creepster",
                    fontSize = 62,
                    fontWeight = "bold",
                    letterSpacing = 6,
                    lineHeight = 1.0,
                    color = "#FFFFFF",
                    x = 512,
                    y = 660,
                    rotation = 0,
                    scale = 1.0,
                    opacity = 1.0,
                    outline = { enabled = true, color = "#000000", width = 7 },
                    shadow = { enabled = true, color = "#000000", blur = 10, offsetX = 3, offsetY = 3 },
                    glow = { enabled = false, color = "#FFFFFF", blur = 0 },
                    drip = { enabled = true, count = 3, length = 50, width = 3 },
                    spray = { enabled = true, count = 8, spread = 15 },
                    distress = { enabled = true, roughness = 0.35 }
                }
            }
        })
    }
}

local function SeedDefaultTemplates()
    for _, tpl in ipairs(DefaultServerTemplates) do
        local exists = Peak.Server.ExecuteSQL("SELECT id FROM peak_spray_designs WHERE is_server_template = 1 AND title = @title", { ["@title"] = tpl.title })
        if not exists or #exists == 0 then
            Peak.Server.InsertSQL([[
                INSERT INTO peak_spray_designs 
                (identifier, player_name, title, category, gang_id, variant, composition, is_server_template)
                VALUES ('SERVER', 'Peak Studios', @title, 'template', NULL, @variant, @composition, 1)
            ]], {
                ["@title"] = tpl.title,
                ["@variant"] = tpl.variant,
                ["@composition"] = tpl.composition
            })
        end
    end
    SprayUtils.DebugPrint("[Designs] Verified server templates")
end

CreateThread(function()
    Wait(2500)
    SeedDefaultTemplates()
end)

-- ============================================================
-- CALLBACKS: DESIGNS LIBRARY
-- ============================================================

Peak.Server.RegisterCallback("peak-sprays:getDesignsLibrary", function(source)
    local identifier = Peak.Server.GetIdentifier(source)
    local gang = Peak.Server.GetPlayerGang(source)

    local query = [[
        SELECT id, identifier, player_name, title, category, gang_id, variant, composition, thumbnail, is_server_template, created_at, updated_at
        FROM peak_spray_designs
        WHERE identifier = @identifier
           OR is_server_template = 1
           OR (category = 'gang' AND gang_id = @gang_id AND @gang_id != 'none')
        ORDER BY updated_at DESC
        LIMIT 100
    ]]

    local rows = Peak.Server.ExecuteSQL(query, {
        ["@identifier"] = identifier,
        ["@gang_id"] = gang.id
    }) or {}

    local library = {
        drafts = {},
        saved = {},
        recent = {},
        templates = {},
        gang = {},
        playerGang = gang,
        playerIdentifier = identifier
    }

    for _, row in ipairs(rows) do
        if Peak.Server.CanReadDesign(source, row) then
            local comp = json.decode(row.composition) or {}
            local layerCount = (comp.layers and type(comp.layers) == "table") and #comp.layers or 0

            local design = {
                id = row.id,
                identifier = row.identifier,
                playerName = row.player_name,
                title = row.title,
                category = row.category,
                variant = row.variant,
                gangId = row.gang_id,
                isServerTemplate = row.is_server_template == 1,
                thumbnail = row.thumbnail,
                layerCount = layerCount,
                createdAt = row.created_at,
                updatedAt = row.updated_at,
                composition = comp
            }

            if row.is_server_template == 1 or row.category == "template" then
                table.insert(library.templates, design)
            elseif row.category == "draft" and row.identifier == identifier then
                table.insert(library.drafts, design)
            elseif row.category == "gang" then
                table.insert(library.gang, design)
            elseif row.category == "saved" and row.identifier == identifier then
                table.insert(library.saved, design)
            end

            -- Add to recent if owned or accessible gang design
            if #library.recent < 12 and (row.identifier == identifier or row.category == "gang") then
                table.insert(library.recent, design)
            end
        end
    end

    return library
end)

Peak.Server.RegisterCallback("peak-sprays:saveDesign", function(source, data)
    if not data or not data.title or not data.composition then
        return { success = false, message = "Missing design data" }
    end

    local identifier = Peak.Server.GetIdentifier(source)
    local playerName = Peak.Server.GetPlayerName(source)

    local comp = data.composition
    if type(comp) == "string" then
        local ok, decoded = pcall(json.decode, comp)
        if not ok or type(decoded) ~= "table" then
            return { success = false, message = "Invalid JSON in composition" }
        end
        comp = decoded
    end

    local valid, valMsg = Peak.Server.ValidatePaintingComposition(comp)
    if not valid then
        return { success = false, message = valMsg or "Invalid composition" }
    end

    local compJson = json.encode(comp)
    if #compJson > 524288 then -- 512KB cap
        return { success = false, message = "Design composition is too large (max 512KB)" }
    end

    -- General personal saves may create/update only 'draft' or 'saved' categories
    local requestedCategory = data.category or "saved"
    if requestedCategory ~= "draft" and requestedCategory ~= "saved" then
        requestedCategory = "saved"
    end

    local variant = data.variant or "default"
    local thumbnail = data.thumbnail
    if thumbnail and type(thumbnail) == "string" and #thumbnail > 100000 then
        thumbnail = thumbnail:sub(1, 100000)
    end

    -- Update if existing ID and owned/permitted
    if data.id and type(data.id) == "number" and data.id > 0 then
        local check = Peak.Server.ExecuteSQL("SELECT id, identifier, category, is_server_template FROM peak_spray_designs WHERE id = @id", { ["@id"] = data.id })
        if check and check[1] then
            local canEdit, editMsg = Peak.Server.CanEditDesign(source, check[1])
            if not canEdit then
                return { success = false, message = editMsg or "Permission denied" }
            end

            Peak.Server.UpdateSQL([[
                UPDATE peak_spray_designs
                SET title = @title, category = @category, variant = @variant, composition = @composition, thumbnail = @thumbnail, updated_at = NOW()
                WHERE id = @id
            ]], {
                ["@id"] = data.id,
                ["@title"] = data.title:sub(1, 64),
                ["@category"] = requestedCategory,
                ["@variant"] = variant,
                ["@composition"] = compJson,
                ["@thumbnail"] = thumbnail
            })

            return { success = true, id = data.id, message = "Design updated" }
        end
    end

    -- Insert new personal design
    local insertId = Peak.Server.InsertSQL([[
        INSERT INTO peak_spray_designs 
        (identifier, player_name, title, category, gang_id, variant, composition, thumbnail, is_server_template)
        VALUES (@identifier, @player_name, @title, @category, NULL, @variant, @composition, @thumbnail, 0)
    ]], {
        ["@identifier"] = identifier,
        ["@player_name"] = playerName,
        ["@title"] = data.title:sub(1, 64),
        ["@category"] = requestedCategory,
        ["@variant"] = variant,
        ["@composition"] = compJson,
        ["@thumbnail"] = thumbnail
    })

    if insertId and insertId > 0 then
        return { success = true, id = insertId, message = "Design saved" }
    end

    return { success = false, message = "Database error" }
end)

Peak.Server.RegisterCallback("peak-sprays:deleteDesign", function(source, designId)
    if not designId or type(designId) ~= "number" then
        return { success = false, message = "Invalid design ID" }
    end

    local check = Peak.Server.ExecuteSQL("SELECT id, identifier, category, is_server_template FROM peak_spray_designs WHERE id = @id", { ["@id"] = designId })
    if not check or not check[1] then
        return { success = false, message = "Design not found" }
    end

    local canDelete, delMsg = Peak.Server.CanDeleteDesign(source, check[1])
    if not canDelete then
        return { success = false, message = delMsg or "Permission denied" }
    end

    Peak.Server.UpdateSQL("DELETE FROM peak_spray_designs WHERE id = @id", { ["@id"] = designId })
    return { success = true, message = "Design deleted" }
end)

-- ============================================================
-- GANG OFFICIAL TEMPLATE PUBLISHING & VARIANTS
-- ============================================================

Peak.Server.RegisterCallback("peak-sprays:publishGangTemplate", function(source, data)
    if not data or not data.title or not data.composition then
        return { success = false, message = "Invalid gang template data" }
    end

    local gang = Peak.Server.GetPlayerGang(source)
    local canPublish, pubMsg = Peak.Server.CanPublishGangTemplate(source, gang.id)
    if not canPublish then
        return { success = false, message = pubMsg or "Permission denied" }
    end

    local comp = data.composition
    if type(comp) == "string" then
        local ok, decoded = pcall(json.decode, comp)
        if not ok or type(decoded) ~= "table" then
            return { success = false, message = "Invalid JSON in composition" }
        end
        comp = decoded
    end

    local valid, valMsg = Peak.Server.ValidatePaintingComposition(comp)
    if not valid then
        return { success = false, message = valMsg or "Invalid composition" }
    end

    local identifier = Peak.Server.GetIdentifier(source)
    local playerName = Peak.Server.GetPlayerName(source)
    local compJson = json.encode(comp)

    local insertId = Peak.Server.InsertSQL([[
        INSERT INTO peak_spray_designs 
        (identifier, player_name, title, category, gang_id, variant, composition, thumbnail, is_server_template)
        VALUES (@identifier, @player_name, @title, 'gang', @gang_id, @variant, @composition, @thumbnail, 0)
    ]], {
        ["@identifier"] = identifier,
        ["@player_name"] = playerName,
        ["@title"] = ("[%s] %s"):format(gang.label, data.title:sub(1, 48)),
        ["@gang_id"] = gang.id,
        ["@variant"] = data.variant or "official",
        ["@composition"] = compJson,
        ["@thumbnail"] = data.thumbnail
    })

    if not insertId or insertId == 0 then
        return { success = false, message = "Failed to save gang template" }
    end

    -- Notify all active gang members
    local allPlayers = GetPlayers()
    for _, pid in ipairs(allPlayers) do
        local pSrc = tonumber(pid)
        if pSrc then
            local pGang = Peak.Server.GetPlayerGang(pSrc)
            if pGang and pGang.id == gang.id then
                TriggerClientEvent("peak-sprays:cl:gangTemplateUpdated", pSrc, {
                    id = insertId,
                    title = data.title,
                    gang = gang.label
                })
            end
        end
    end

    return { success = true, id = insertId, message = "Official gang template published" }
end)

-- ============================================================
-- IMPORT / EXPORT JSON
-- ============================================================

Peak.Server.RegisterCallback("peak-sprays:exportDesignJson", function(source, designId)
    if not designId or type(designId) ~= "number" then
        return { success = false, message = "Invalid design ID" }
    end

    local query = "SELECT id, identifier, title, category, gang_id, is_server_template, composition FROM peak_spray_designs WHERE id = @id"
    local rows = Peak.Server.ExecuteSQL(query, { ["@id"] = designId })
    if not rows or not rows[1] then
        return { success = false, message = "Design not found" }
    end

    local row = rows[1]
    local canRead, readMsg = Peak.Server.CanReadDesign(source, row)
    if not canRead then
        return { success = false, message = readMsg or "Permission denied" }
    end

    local comp = json.decode(row.composition) or {}
    local exportPayload = {
        peak_spray_format = "v1",
        title = row.title,
        exported_by = Peak.Server.GetPlayerName(source),
        exported_at = os.time(),
        composition = comp
    }

    return { success = true, json = json.encode(exportPayload) }
end)

Peak.Server.RegisterCallback("peak-sprays:importDesignJson", function(source, jsonString)
    if type(jsonString) ~= "string" or jsonString == "" then
        return { success = false, message = "Invalid JSON data" }
    end
    if #jsonString > 524288 then
        return { success = false, message = "JSON payload exceeds 512KB limit" }
    end

    local ok, payload = pcall(json.decode, jsonString)
    if not ok or type(payload) ~= "table" then
        return { success = false, message = "Failed to parse JSON design" }
    end

    local comp = payload.composition or payload
    local valid, valMsg = Peak.Server.ValidatePaintingComposition(comp)
    if not valid then
        return { success = false, message = valMsg or "Invalid composition structure" }
    end

    local identifier = Peak.Server.GetIdentifier(source)
    local playerName = Peak.Server.GetPlayerName(source)
    local title = (payload.title or comp.title or "Imported Design"):sub(1, 64)

    local insertId = Peak.Server.InsertSQL([[
        INSERT INTO peak_spray_designs 
        (identifier, player_name, title, category, gang_id, variant, composition, is_server_template)
        VALUES (@identifier, @player_name, @title, 'saved', NULL, 'default', @composition, 0)
    ]], {
        ["@identifier"] = identifier,
        ["@player_name"] = playerName,
        ["@title"] = title,
        ["@composition"] = json.encode(comp)
    })

    if insertId and insertId > 0 then
        return { success = true, id = insertId, message = "Design imported successfully" }
    end

    return { success = false, message = "Failed to store imported design" }
end)
