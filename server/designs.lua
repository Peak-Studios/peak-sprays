Peak = Peak or {}
Peak.Server = Peak.Server or {}

-- ============================================================
-- GANG HELPERS
-- ============================================================

--- Returns player gang info { id = string, name = string, label = string, isBoss = boolean, grade = number }
function Peak.Server.GetPlayerGang(src)
    local fw = Peak.Server.FrameworkName
    local obj = Peak.Server.FrameworkObject

    if fw == "qbcore" or fw == "qbox" then
        local player = obj.Functions.GetPlayer(src)
        if player and player.PlayerData and player.PlayerData.gang then
            local gang = player.PlayerData.gang
            local isBoss = gang.isboss == true or (gang.grade and (gang.grade.isboss == true or (gang.grade.level and gang.grade.level >= 3)))
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
                return {
                    id = gangJob.name,
                    name = gangJob.name,
                    label = gangJob.label or gangJob.name,
                    isBoss = (gangJob.grade_name and gangJob.grade_name:lower():find("boss")) ~= nil or gangJob.grade >= 3,
                    grade = gangJob.grade or 0
                }
            end
            -- Fallback to standard job if named gang-like
            local job = player.getJob()
            if job and job.name and job.name ~= "unemployed" then
                return {
                    id = job.name,
                    name = job.name,
                    label = job.label or job.name,
                    isBoss = (job.grade_name and job.grade_name:lower():find("boss")) ~= nil or job.grade >= 3,
                    grade = job.grade or 0
                }
            end
        end
    end

    return { id = "none", name = "none", label = "None", isBoss = false, grade = 0 }
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
    local countRes = Peak.Server.ExecuteSQL("SELECT COUNT(*) as count FROM peak_spray_designs WHERE is_server_template = 1", {})
    local count = (countRes and countRes[1] and countRes[1].count) or 0
    if count == 0 then
        for _, tpl in ipairs(DefaultServerTemplates) do
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
        SprayUtils.DebugPrint("[Designs] Seeded default server templates")
    end
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
        playerGang = gang
    }

    for _, row in ipairs(rows) do
        local design = {
            id = row.id,
            title = row.title,
            category = row.category,
            variant = row.variant,
            gangId = row.gang_id,
            playerName = row.player_name,
            isServerTemplate = row.is_server_template == 1,
            thumbnail = row.thumbnail,
            createdAt = row.created_at,
            updatedAt = row.updated_at,
            composition = json.decode(row.composition) or {}
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

        -- Add to recent if created or updated recently
        if #library.recent < 12 and (row.identifier == identifier or row.category == "gang") then
            table.insert(library.recent, design)
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
    local category = data.category or "saved"
    local variant = data.variant or "default"
    local gangId = (category == "gang") and data.gangId or nil
    local thumbnail = data.thumbnail

    local compJson = type(data.composition) == "string" and data.composition or json.encode(data.composition)
    if #compJson > 500000 then -- 500KB cap
        return { success = false, message = "Design composition is too large" }
    end

    -- Update if existing ID and owned by player
    if data.id and type(data.id) == "number" and data.id > 0 then
        local check = Peak.Server.ExecuteSQL("SELECT identifier, is_server_template FROM peak_spray_designs WHERE id = @id", { ["@id"] = data.id })
        if check and check[1] then
            if check[1].is_server_template == 1 and not Peak.Server.IsAdmin(source) then
                return { success = false, message = "Cannot overwrite server templates" }
            end
            if check[1].identifier ~= identifier and not Peak.Server.IsAdmin(source) then
                return { success = false, message = "Permission denied" }
            end

            Peak.Server.UpdateSQL([[
                UPDATE peak_spray_designs
                SET title = @title, category = @category, variant = @variant, composition = @composition, thumbnail = @thumbnail
                WHERE id = @id
            ]], {
                ["@id"] = data.id,
                ["@title"] = data.title,
                ["@category"] = category,
                ["@variant"] = variant,
                ["@composition"] = compJson,
                ["@thumbnail"] = thumbnail
            })

            return { success = true, id = data.id, message = "Design updated" }
        end
    end

    local insertId = Peak.Server.InsertSQL([[
        INSERT INTO peak_spray_designs 
        (identifier, player_name, title, category, gang_id, variant, composition, thumbnail, is_server_template)
        VALUES (@identifier, @player_name, @title, @category, @gang_id, @variant, @composition, @thumbnail, 0)
    ]], {
        ["@identifier"] = identifier,
        ["@player_name"] = playerName,
        ["@title"] = data.title,
        ["@category"] = category,
        ["@gang_id"] = gangId,
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

    local identifier = Peak.Server.GetIdentifier(source)
    local check = Peak.Server.ExecuteSQL("SELECT identifier, is_server_template FROM peak_spray_designs WHERE id = @id", { ["@id"] = designId })
    if not check or not check[1] then
        return { success = false, message = "Design not found" }
    end

    if check[1].is_server_template == 1 and not Peak.Server.IsAdmin(source) then
        return { success = false, message = "Cannot delete server templates" }
    end

    if check[1].identifier ~= identifier and not Peak.Server.IsAdmin(source) then
        return { success = false, message = "Permission denied" }
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
    if not gang or gang.id == "none" then
        return { success = false, message = "You are not in a gang or crew" }
    end

    if not gang.isBoss and not Peak.Server.IsAdmin(source) then
        return { success = false, message = "Only gang leaders can publish official crew tags" }
    end

    local identifier = Peak.Server.GetIdentifier(source)
    local playerName = Peak.Server.GetPlayerName(source)
    local compJson = type(data.composition) == "string" and data.composition or json.encode(data.composition)

    -- Save the primary official tag
    local insertId = Peak.Server.InsertSQL([[
        INSERT INTO peak_spray_designs 
        (identifier, player_name, title, category, gang_id, variant, composition, thumbnail, is_server_template)
        VALUES (@identifier, @player_name, @title, 'gang', @gang_id, @variant, @composition, @thumbnail, 0)
    ]], {
        ["@identifier"] = identifier,
        ["@player_name"] = playerName,
        ["@title"] = ("[%s] %s"):format(gang.label, data.title),
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
    local query = "SELECT title, composition FROM peak_spray_designs WHERE id = @id"
    local rows = Peak.Server.ExecuteSQL(query, { ["@id"] = designId })
    if not rows or not rows[1] then
        return { success = false, message = "Design not found" }
    end

    local comp = json.decode(rows[1].composition) or {}
    local exportPayload = {
        peak_spray_format = "v1",
        title = rows[1].title,
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

    local ok, payload = pcall(json.decode, jsonString)
    if not ok or type(payload) ~= "table" then
        return { success = false, message = "Failed to parse JSON design" }
    end

    local comp = payload.composition or payload
    if not comp or (not comp.layers and not comp.strokes) then
        return { success = false, message = "Invalid Peak Spray composition structure" }
    end

    local identifier = Peak.Server.GetIdentifier(source)
    local playerName = Peak.Server.GetPlayerName(source)
    local title = payload.title or comp.title or "Imported Design"

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
