Peak = Peak or {}
Peak.Territory = Peak.Territory or {}

local activeContests = {}

local function gangColor(gangId)
    local hue = (tonumber(gangId) or 1) * 67 % 360
    return ("hsl(%d 72%% 48%%)"):format(hue)
end

local function decode(value, fallback)
    if not value or value == "" then return fallback end
    local ok, result = pcall(json.decode, value)
    if ok and result ~= nil then return result end
    return fallback
end

local function distance(a, b)
    local dx = (a.x or 0.0) - (b.x or 0.0)
    local dy = (a.y or 0.0) - (b.y or 0.0)
    local dz = (a.z or 0.0) - (b.z or 0.0)
    return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
end

local function playerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local coords = GetEntityCoords(ped)
    return { x = coords.x, y = coords.y, z = coords.z }
end

local function getNearbySprays(coords, radius)
    return Peak.Server.ExecuteSQL([[
        SELECT id, gang_id, status, contest_data, world_x, world_y, world_z
        FROM spray_paintings
        WHERE gang_id IS NOT NULL
          AND world_x BETWEEN @minX AND @maxX
          AND world_y BETWEEN @minY AND @maxY
    ]], {
        ["@minX"] = coords.x - radius,
        ["@maxX"] = coords.x + radius,
        ["@minY"] = coords.y - radius,
        ["@maxY"] = coords.y + radius,
    }) or {}
end

local function enrichSpray(row, viewerGang)
    local gangId = tonumber(row.gang_id)
    local gang = Peak.Gangs and Peak.Gangs.GetGang(gangId) or nil
    local contest = decode(row.contest_data, nil)
    local discovered = false

    if viewerGang and viewerGang.discovered_sprays then
        for _, sprayId in ipairs(viewerGang.discovered_sprays) do
            if tonumber(sprayId) == tonumber(row.id) then
                discovered = true
                break
            end
        end
    end

    return {
        id = tonumber(row.id),
        gang_id = gangId,
        gangId = gangId,
        gangName = gang and gang.name or ("Gang " .. tostring(gangId or "?")),
        gangColor = gang and gang.color or gangColor(gangId),
        status = row.status or "normal",
        contest = contest,
        world_x = tonumber(row.world_x) or 0.0,
        world_y = tonumber(row.world_y) or 0.0,
        world_z = tonumber(row.world_z) or 0.0,
        radius = Config.InfluenceRadius or 90.0,
        contestedRadius = Config.ContestedInfluenceRadius or 50.0,
        placementRadius = Config.PlacementDistance or 75.0,
        created_at = row.created_at,
        discovered = discovered,
        isOwnGang = viewerGang and tonumber(viewerGang.id) == gangId or false,
    }
end

local function getDailyCount(source, gangId)
    if Config.DailyLimitType == "gang" and gangId then
        local rows = Peak.Server.ExecuteSQL([[
            SELECT COUNT(*) AS total
            FROM spray_paintings
            WHERE gang_id = @gang_id AND created_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
        ]], { ["@gang_id"] = gangId })
        return rows and rows[1] and tonumber(rows[1].total) or 0
    end

    local identifier = Peak.Server.GetIdentifier(source)
    local rows = Peak.Server.ExecuteSQL([[
        SELECT COUNT(*) AS total
        FROM spray_paintings
        WHERE identifier = @identifier AND created_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
    ]], { ["@identifier"] = identifier })
    return rows and rows[1] and tonumber(rows[1].total) or 0
end

local function startContest(source, spray, attackerGangId, coords)
    local contest = {
        sprayId = spray.id,
        attacker = source,
        attackerGangId = attackerGangId,
        defenderGangId = spray.gang_id,
        startTime = os.time(),
        center = { x = spray.world_x, y = spray.world_y, z = spray.world_z },
    }
    activeContests[spray.id] = contest

    if Peak.Gangs then
        Peak.Gangs.SetContestStats(attackerGangId)
        Peak.Gangs.AddActivity(attackerGangId, {
            type = "contest",
            title = "Contest started",
            message = "Your gang started contesting enemy turf.",
        })
        Peak.Gangs.AddActivity(spray.gang_id, {
            type = "contest",
            title = "Territory contested",
            message = "A rival gang is contesting one of your sprays.",
        })
    end

    Peak.Server.UpdateSQL([[
        UPDATE spray_paintings
        SET status = 'contested', contest_data = @contest_data
        WHERE id = @id
    ]], {
        ["@id"] = spray.id,
        ["@contest_data"] = json.encode(contest),
    })

    if Peak.Phone then
        Peak.Phone.SendGangBroadcast(spray.gang_id, "Territory contested", "A rival gang is contesting one of your sprays.")
    end
    TriggerClientEvent("peak-sprays:cl:contestStarted", -1, contest)

    CreateThread(function()
        local duration = Config.ContestDuration or 900
        local radius = Config.InfluenceRadius or 90.0
        while activeContests[spray.id] do
            Wait((Config.ContestCheckInterval or 10) * 1000)
            local current = activeContests[spray.id]
            if not current then return end

            local attackerCoords = playerCoords(current.attacker)
            if not attackerCoords or distance(attackerCoords, current.center) > radius then
                activeContests[spray.id] = nil
                Peak.Server.UpdateSQL("UPDATE spray_paintings SET status = 'normal', contest_data = NULL WHERE id = @id", {
                    ["@id"] = spray.id
                })
                TriggerClientEvent("peak-sprays:cl:contestEnded", -1, { sprayId = spray.id, success = false })
                if Peak.Gangs then
                    Peak.Gangs.AddActivity(current.attackerGangId, {
                        type = "contest",
                        title = "Contest failed",
                        message = "The contest failed because the attacker left the turf radius.",
                    })
                end
                if Peak.Phone then
                    Peak.Phone.SendGangBroadcast(spray.gang_id, "Contest failed", "The rival left the influence radius and the contest failed.")
                end
                return
            end

            if os.time() - current.startTime >= duration then
                activeContests[spray.id] = nil
                Peak.Server.UpdateSQL("DELETE FROM spray_paintings WHERE id = @id", { ["@id"] = spray.id })
                if Peak.Gangs then
                    Peak.Gangs.RemoveDiscoveredSpray(spray.id)
                    Peak.Gangs.AddSprayXp(current.defenderGangId, { setLastSpray = false })
                    Peak.Gangs.AddActivity(current.attackerGangId, {
                        type = "contest",
                        title = "Contest won",
                        message = "Enemy turf was cleared. Place your spray to claim it.",
                    })
                    Peak.Gangs.AddActivity(current.defenderGangId, {
                        type = "contest",
                        title = "Territory lost",
                        message = "A contested spray was removed from your turf.",
                    })
                end
                TriggerClientEvent("peak-sprays:cl:removePainting", -1, spray.id)
                TriggerClientEvent("peak-sprays:cl:contestEnded", -1, { sprayId = spray.id, success = true })
                TriggerClientEvent("peak-sprays:cl:territoryContestWon", current.attacker, current)
                return
            end
        end
    end)

    return {
        success = false,
        contested = true,
        message = ("Enemy territory contested. Stay within %.0fm for %d minutes."):format(Config.InfluenceRadius or 90.0, math.floor((Config.ContestDuration or 900) / 60))
    }
end

function Peak.Territory.ValidatePlacement(source, data)
    local gangId = Peak.Gangs and Peak.Gangs.GetPlayerGangId(source) or nil
    if Config.DailyLimitCount and Config.DailyLimitCount > 0 then
        local dailyCount = getDailyCount(source, gangId)
        if dailyCount >= Config.DailyLimitCount then
            return { success = false, message = "Daily spray limit reached." }
        end
    end

    if not gangId then
        return { success = true, gangId = nil }
    end

    local coords = { x = data.worldX, y = data.worldY, z = data.worldZ }
    local influenceRadius = Config.InfluenceRadius or 90.0
    local placementDistance = Config.PlacementDistance or 75.0
    local rows = getNearbySprays(coords, math.max(influenceRadius, placementDistance))
    for _, spray in ipairs(rows) do
        spray.world_x = tonumber(spray.world_x)
        spray.world_y = tonumber(spray.world_y)
        spray.world_z = tonumber(spray.world_z)
        spray.gang_id = tonumber(spray.gang_id)
        local sprayCoords = { x = spray.world_x, y = spray.world_y, z = spray.world_z }
        local sprayDistance = distance(coords, sprayCoords)
        if spray.gang_id == gangId and sprayDistance <= placementDistance then
            return {
                success = false,
                message = ("Too close to your own turf. Move at least %.0fm away."):format(placementDistance)
            }
        end

        if spray.gang_id ~= gangId and sprayDistance <= influenceRadius then
            if spray.status == "contested" then
                return { success = false, message = "This territory is already contested." }
            end
            return startContest(source, spray, gangId, coords)
        end
    end

    return { success = true, gangId = gangId }
end

Peak.Server.RegisterCallback("peak-sprays:territory:getMap", function(source)
    local viewerGang = Peak.Gangs and Peak.Gangs.GetPlayerGang(source) or nil
    local rows = Peak.Server.ExecuteSQL([[
        SELECT id, gang_id, status, contest_data, world_x, world_y, world_z, created_at
        FROM spray_paintings
        WHERE gang_id IS NOT NULL
    ]], {}) or {}

    local result = {}
    for _, row in ipairs(rows) do
        table.insert(result, enrichSpray(row, viewerGang))
    end
    return result
end)

Peak.Server.RegisterCallback("peak-sprays:territory:getSummary", function(source)
    local gang = Peak.Gangs and Peak.Gangs.GetPlayerGang(source) or nil
    local rows = Peak.Server.ExecuteSQL([[
        SELECT gang_id, status, COUNT(*) AS total
        FROM spray_paintings
        WHERE gang_id IS NOT NULL
        GROUP BY gang_id, status
    ]], {}) or {}

    local summary = {
        total = 0,
        contested = 0,
        gangs = {},
        ownGangId = gang and gang.id or nil,
        discovered = gang and #(gang.discovered_sprays or {}) or 0,
    }

    for _, row in ipairs(rows) do
        local gangId = tonumber(row.gang_id)
        local status = row.status or "normal"
        local count = tonumber(row.total) or 0
        local gangData = Peak.Gangs and Peak.Gangs.GetGang(gangId) or nil
        summary.total = summary.total + count
        if status == "contested" then summary.contested = summary.contested + count end
        summary.gangs[gangId] = summary.gangs[gangId] or {
            id = gangId,
            name = gangData and gangData.name or ("Gang " .. tostring(gangId)),
            color = gangData and gangData.color or gangColor(gangId),
            total = 0,
            contested = 0,
        }
        summary.gangs[gangId].total = summary.gangs[gangId].total + count
        if status == "contested" then
            summary.gangs[gangId].contested = summary.gangs[gangId].contested + count
        end
    end

    return summary
end)

Peak.Server.RegisterCallback("peak-sprays:territory:toggleDiscovered", function(source, sprayId)
    local gang = Peak.Gangs and Peak.Gangs.GetPlayerGang(source) or nil
    if not gang then return { success = false, message = "No gang found." } end
    if not sprayId then return { success = true, discovered = gang.discovered_sprays or {} } end
    Peak.Gangs.AddDiscoveredSpray(gang.id, sprayId)
    return { success = true, discovered = gang.discovered_sprays or {} }
end)

Peak.Server.RegisterCallback("peak-sprays:territory:toggleContested", function(source)
    local gang = Peak.Gangs and Peak.Gangs.GetPlayerGang(source) or nil
    if not gang then return { success = false, message = "No gang found.", sprays = {} } end
    local rows = Peak.Server.ExecuteSQL([[
        SELECT id, gang_id, status, contest_data, world_x, world_y, world_z, created_at
        FROM spray_paintings
        WHERE status = 'contested'
          AND (gang_id = @gang_id OR contest_data LIKE @attacker)
    ]], {
        ["@gang_id"] = gang.id,
        ["@attacker"] = '%"attackerGangId":' .. tostring(gang.id) .. '%',
    }) or {}

    local result = {}
    for _, row in ipairs(rows) do
        table.insert(result, enrichSpray(row, gang))
    end
    return { success = true, sprays = result }
end)

exports("GetTerritoryDistance", function(a, b)
    return distance(a, b)
end)
