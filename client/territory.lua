Peak = Peak or {}
Peak.TerritoryClient = Peak.TerritoryClient or {
    contests = {},
    spatialCache = {},
    cacheBuiltAt = 0,
}

local function cachePaintings()
    local cellSize = Config.InfluenceRadius or 90.0
    local cache = {}
    for id, painting in pairs(KnownPaintings or {}) do
        if painting.center then
            local cx = math.floor(painting.center.x / cellSize)
            local cy = math.floor(painting.center.y / cellSize)
            local key = cx .. ":" .. cy
            cache[key] = cache[key] or {}
            table.insert(cache[key], painting)
        end
    end
    Peak.TerritoryClient.spatialCache = cache
    Peak.TerritoryClient.cacheBuiltAt = GetGameTimer()
end

function Peak.TerritoryClient.GetNearbyFromCache(coords, radius)
    if GetGameTimer() - (Peak.TerritoryClient.cacheBuiltAt or 0) > 5000 then
        cachePaintings()
    end

    local result = {}
    local cellSize = Config.InfluenceRadius or 90.0
    local baseX = math.floor(coords.x / cellSize)
    local baseY = math.floor(coords.y / cellSize)
    for x = baseX - 1, baseX + 1 do
        for y = baseY - 1, baseY + 1 do
            local bucket = Peak.TerritoryClient.spatialCache[x .. ":" .. y]
            if bucket then
                for _, painting in ipairs(bucket) do
                    if painting.center and #(coords - painting.center) <= radius then
                        table.insert(result, painting)
                    end
                end
            end
        end
    end
    return result
end

function IsInEnemyTerritory(coords)
    if not coords or not Peak.ClientGang or not Peak.ClientGang.gang then return false end
    local gangId = tonumber(Peak.ClientGang.gang.id)
    for _, painting in ipairs(Peak.TerritoryClient.GetNearbyFromCache(coords, Config.InfluenceRadius or 90.0)) do
        if painting.gangId and tonumber(painting.gangId) ~= gangId then
            return true, painting
        end
    end
    return false
end

RegisterNetEvent("peak-sprays:cl:newPainting", function()
    SetTimeout(100, cachePaintings)
end)

RegisterNetEvent("peak-sprays:cl:removePainting", function()
    SetTimeout(100, cachePaintings)
end)

RegisterNetEvent("peak-sprays:cl:contestStarted", function(contest)
    Peak.TerritoryClient.contests[contest.sprayId] = contest
    Peak.Client.Notify("Territory contest started. Stay inside the marked radius.", "warning", Config.NotifyDuration)
end)

RegisterNetEvent("peak-sprays:cl:contestEnded", function(result)
    Peak.TerritoryClient.contests[result.sprayId] = nil
end)

RegisterNetEvent("peak-sprays:cl:territoryContestWon", function()
    Peak.Client.Notify("Contest won. Place your spray now to claim the territory.", "success", Config.NotifyDuration)
end)

CreateThread(function()
    while true do
        Wait(0)
        local any = false
        for _, contest in pairs(Peak.TerritoryClient.contests) do
            any = true
            local center = vector3(contest.center.x, contest.center.y, contest.center.z)
            DrawMarker(1, center.x, center.y, center.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, (Config.InfluenceRadius or 90.0) * 2.0, (Config.InfluenceRadius or 90.0) * 2.0, 1.5, 185, 28, 28, 70, false, false, 2, false, nil, nil, false)
            DrawMarker(2, center.x, center.y, center.z + 1.0, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0, 1.5, 1.5, 1.5, 255, 255, 255, 180, true, true, 2, false, nil, nil, false)
        end
        if SprayState and SprayState.mode == "selecting" then
            local pedCoords = GetEntityCoords(PlayerPedId())
            for _, painting in ipairs(Peak.TerritoryClient.GetNearbyFromCache(pedCoords, Config.InfluenceRadius or 90.0)) do
                if painting.center and painting.gangId and (not Peak.ClientGang.gang or tonumber(painting.gangId) ~= tonumber(Peak.ClientGang.gang.id)) then
                    any = true
                    DrawMarker(1, painting.center.x, painting.center.y, painting.center.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, (Config.InfluenceRadius or 90.0) * 2.0, (Config.InfluenceRadius or 90.0) * 2.0, 1.0, 220, 38, 38, 35, false, false, 2, false, nil, nil, false)
                end
            end
        end
        if not any then Wait(500) end
    end
end)
