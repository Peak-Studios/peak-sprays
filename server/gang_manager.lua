Peak = Peak or {}
Peak.Gangs = Peak.Gangs or {}

local gangCache = {}
local playerGang = {}

local ranks = {
    leader = 4,
    officer = 3,
    member = 1,
}

local defaultMetadata = {
    description = "",
    requiredMembers = 4,
    xp = 0,
    crimeXp = 0,
    tier = 1,
    balance = 0,
    spraysContested = 0,
    lastSprayTimestamp = 0,
    lastSprayContest = 0,
    activity = {},
}

local function decode(value, fallback)
    if not value or value == "" then return fallback end
    local ok, result = pcall(json.decode, value)
    if ok and result ~= nil then return result end
    return fallback
end

local function encode(value)
    return json.encode(value or {})
end

local function calculateTier(score)
    if score >= 10000 then return 5 end
    if score >= 5000 then return 4 end
    if score >= 2500 then return 3 end
    if score >= 1000 then return 2 end
    return 1
end

local function gangColor(gangId)
    local hue = (tonumber(gangId) or 1) * 67 % 360
    return ("hsl(%d 72%% 48%%)"):format(hue)
end

local function hydrate(row)
    local metadata = decode(row.metadata, {})
    for key, value in pairs(defaultMetadata) do
        if metadata[key] == nil then
            if type(value) == "table" then
                metadata[key] = {}
            else
                metadata[key] = value
            end
        end
    end

    local gang = {
        id = row.id,
        name = row.name,
        leader = row.leader,
        members = decode(row.members, {}),
        metadata = metadata,
        official_mark = decode(row.official_mark, nil),
        discovered_sprays = decode(row.discovered_sprays, {}),
    }
    gang.metadata.xp = tonumber(gang.metadata.xp) or 0
    gang.metadata.crimeXp = tonumber(gang.metadata.crimeXp) or 0
    gang.metadata.balance = tonumber(gang.metadata.balance) or 0
    gang.metadata.tier = tonumber(gang.metadata.tier) or 1
    gang.metadata.spraysContested = tonumber(gang.metadata.spraysContested) or 0
    gang.metadata.lastSprayTimestamp = tonumber(gang.metadata.lastSprayTimestamp) or 0
    gang.metadata.lastSprayContest = tonumber(gang.metadata.lastSprayContest) or 0
    gang.color = gangColor(gang.id)
    return gang
end

local function rebuildPlayerIndex()
    playerGang = {}
    for gangId, gang in pairs(gangCache) do
        for _, member in ipairs(gang.members or {}) do
            if member.identifier then
                playerGang[member.identifier] = gangId
            end
        end
    end
end

local function saveGang(gang)
    Peak.Server.UpdateSQL([[
        UPDATE peak_gangs
        SET name = @name, leader = @leader, members = @members, metadata = @metadata, official_mark = @official_mark, discovered_sprays = @discovered_sprays
        WHERE id = @id
    ]], {
        ["@id"] = gang.id,
        ["@name"] = gang.name,
        ["@leader"] = gang.leader,
        ["@members"] = encode(gang.members),
        ["@metadata"] = encode(gang.metadata),
        ["@official_mark"] = gang.official_mark and encode(gang.official_mark) or nil,
        ["@discovered_sprays"] = encode(gang.discovered_sprays),
    })
    gangCache[gang.id] = gang
    rebuildPlayerIndex()
end

local function findMember(gang, identifier)
    for index, member in ipairs(gang.members or {}) do
        if member.identifier == identifier then return member, index end
    end
    return nil, nil
end

local function canManage(src, gang, minRank)
    if Peak.Server.IsAdmin(src) then return true end
    local identifier = Peak.Server.GetIdentifier(src)
    local member = findMember(gang, identifier)
    return member and (ranks[member.rank] or 0) >= minRank
end

function Peak.Gangs.Refresh()
    local rows = Peak.Server.ExecuteSQL("SELECT id, name, leader, members, metadata, official_mark, discovered_sprays FROM peak_gangs", {}) or {}
    gangCache = {}
    for _, row in ipairs(rows) do
        local gang = hydrate(row)
        gangCache[gang.id] = gang
    end
    rebuildPlayerIndex()
end

function Peak.Gangs.Save(gang)
    if gang then saveGang(gang) end
end

function Peak.Gangs.GetGang(gangId)
    return gangCache[tonumber(gangId)]
end

function Peak.Gangs.GetPlayerGang(src)
    local identifier = Peak.Server.GetIdentifier(src)
    local gangId = identifier and playerGang[identifier]
    return gangId and gangCache[gangId] or nil
end

function Peak.Gangs.GetPlayerGangId(src)
    local gang = Peak.Gangs.GetPlayerGang(src)
    return gang and gang.id or nil
end

function Peak.Gangs.GetOnlineMembers(gangId)
    local gang = gangCache[tonumber(gangId)]
    local result = {}
    if not gang then return result end
    local memberIds = {}
    for _, member in ipairs(gang.members or {}) do
        memberIds[member.identifier] = true
    end
    for _, src in ipairs(GetPlayers()) do
        if memberIds[Peak.Server.GetIdentifier(tonumber(src))] then
            table.insert(result, tonumber(src))
        end
    end
    return result
end

function Peak.Gangs.GetRank(source, gang)
    if not gang then return nil, 0 end
    if Peak.Server.IsAdmin(source) then return "admin", 99 end
    local identifier = Peak.Server.GetIdentifier(source)
    local member = findMember(gang, identifier)
    return member and member.rank or nil, member and (ranks[member.rank] or 0) or 0
end

function Peak.Gangs.AddActivity(gangId, activity)
    local gang = gangCache[tonumber(gangId)]
    if not gang then return end

    activity = type(activity) == "table" and activity or {}
    activity.time = activity.time or os.time()
    activity.type = activity.type or "activity"
    activity.title = activity.title or "Gang activity"
    activity.message = activity.message or ""

    gang.metadata.activity = gang.metadata.activity or {}
    table.insert(gang.metadata.activity, 1, activity)
    while #gang.metadata.activity > 30 do
        table.remove(gang.metadata.activity)
    end
    saveGang(gang)
end

function Peak.Gangs.AddDiscoveredSpray(gangId, sprayId)
    local gang = gangCache[tonumber(gangId)]
    if not gang or not sprayId then return false end

    gang.discovered_sprays = gang.discovered_sprays or {}
    for _, id in ipairs(gang.discovered_sprays) do
        if tonumber(id) == tonumber(sprayId) then return true end
    end

    table.insert(gang.discovered_sprays, tonumber(sprayId))
    saveGang(gang)
    return true
end

function Peak.Gangs.RemoveDiscoveredSpray(sprayId)
    for _, gang in pairs(gangCache) do
        local changed = false
        for index = #(gang.discovered_sprays or {}), 1, -1 do
            if tonumber(gang.discovered_sprays[index]) == tonumber(sprayId) then
                table.remove(gang.discovered_sprays, index)
                changed = true
            end
        end
        if changed then saveGang(gang) end
    end
end

function Peak.Gangs.AddSprayXp(gangId, options)
    local gang = gangCache[tonumber(gangId)]
    if not gang then return end
    options = options or {}
    local count = Peak.Server.ExecuteSQL("SELECT COUNT(*) AS total FROM spray_paintings WHERE gang_id = @gang_id", {
        ["@gang_id"] = gang.id
    })
    local totalSprays = count and count[1] and tonumber(count[1].total) or 0
    local score = (totalSprays * 100) + (tonumber(gang.metadata.crimeXp) or 0)
    gang.metadata.xp = score
    gang.metadata.tier = calculateTier(score)
    if options.setLastSpray ~= false then
        gang.metadata.lastSprayTimestamp = os.time()
    end
    saveGang(gang)
    TriggerClientEvent("peak-sprays:cl:gangUpdated", -1, gang)
end

function Peak.Gangs.SetContestStats(gangId)
    local gang = gangCache[tonumber(gangId)]
    if not gang then return end
    gang.metadata.spraysContested = (tonumber(gang.metadata.spraysContested) or 0) + 1
    gang.metadata.lastSprayContest = os.time()
    saveGang(gang)
end

CreateThread(function()
    Wait(1200)
    Peak.Gangs.Refresh()
end)

Peak.Server.RegisterCallback("peak-sprays:gang:getSelf", function(source)
    local gang = Peak.Gangs.GetPlayerGang(source)
    return {
        gang = gang,
        phone = Peak.Phone and Peak.Phone.GetActiveDriver() or "native",
    }
end)

Peak.Server.RegisterCallback("peak-sprays:gang:getAll", function()
    local result = {}
    for _, gang in pairs(gangCache) do
        table.insert(result, gang)
    end
    return result
end)

Peak.Server.RegisterCallback("peak-sprays:gang:create", function(source, name)
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if #name < 3 or #name > 80 then
        return { success = false, message = "Gang name must be 3-80 characters." }
    end

    local identifier = Peak.Server.GetIdentifier(source)
    if playerGang[identifier] then
        return { success = false, message = "You are already in a gang." }
    end

    local existing = Peak.Server.ExecuteSQL("SELECT id FROM peak_gangs WHERE name = @name LIMIT 1", { ["@name"] = name })
    if existing and existing[1] then
        return { success = false, message = "A gang with that name already exists." }
    end

    local member = { identifier = identifier, name = Peak.Server.GetPlayerName(source), rank = "leader" }
    local metadata = {}
    for key, value in pairs(defaultMetadata) do
        metadata[key] = type(value) == "table" and {} or value
    end
    metadata.description = ("Created by %s"):format(Peak.Server.GetPlayerName(source) or "Unknown")
    local id = Peak.Server.InsertSQL([[
        INSERT INTO peak_gangs (name, leader, members, metadata, discovered_sprays)
        VALUES (@name, @leader, @members, @metadata, @discovered_sprays)
    ]], {
        ["@name"] = name,
        ["@leader"] = identifier,
        ["@members"] = encode({ member }),
        ["@metadata"] = encode(metadata),
        ["@discovered_sprays"] = encode({}),
    })
    if not id or id == 0 then return { success = false, message = "Failed to create gang." } end

    local gang = { id = id, name = name, leader = identifier, members = { member }, metadata = metadata, official_mark = nil, discovered_sprays = {}, color = gangColor(id) }
    gangCache[id] = gang
    rebuildPlayerIndex()
    Peak.Gangs.AddActivity(id, {
        type = "gang",
        title = "Gang created",
        message = ("%s founded %s."):format(member.name, name),
    })
    TriggerClientEvent("peak-sprays:cl:gangUpdated", source, gang)
    return { success = true, gang = gang }
end)

Peak.Server.RegisterCallback("peak-sprays:gang:addMember", function(source, targetId)
    local gang = Peak.Gangs.GetPlayerGang(source)
    if not gang or not canManage(source, gang, ranks.officer) then
        return { success = false, message = "You cannot invite members." }
    end

    targetId = tonumber(targetId)
    if not targetId or not GetPlayerName(targetId) then
        return { success = false, message = "Player is not online." }
    end

    local identifier = Peak.Server.GetIdentifier(targetId)
    if playerGang[identifier] then
        return { success = false, message = "Player is already in a gang." }
    end

    table.insert(gang.members, { identifier = identifier, name = Peak.Server.GetPlayerName(targetId), rank = "member" })
    Peak.Gangs.AddActivity(gang.id, {
        type = "member",
        title = "Member invited",
        message = ("%s joined the roster."):format(Peak.Server.GetPlayerName(targetId) or "Unknown"),
    })
    saveGang(gang)
    TriggerClientEvent("peak-sprays:cl:gangUpdated", targetId, gang)
    return { success = true, gang = gang }
end)

Peak.Server.RegisterCallback("peak-sprays:gang:kick", function(source, identifier)
    local gang = Peak.Gangs.GetPlayerGang(source)
    if not gang or not canManage(source, gang, ranks.officer) then
        return { success = false, message = "You cannot remove members." }
    end
    if identifier == gang.leader then return { success = false, message = "The leader cannot be removed." } end

    local _, index = findMember(gang, identifier)
    if not index then return { success = false, message = "Member not found." } end
    table.remove(gang.members, index)
    Peak.Gangs.AddActivity(gang.id, {
        type = "member",
        title = "Member removed",
        message = "A member was removed from the roster.",
    })
    saveGang(gang)
    return { success = true, gang = gang }
end)

Peak.Server.RegisterCallback("peak-sprays:gang:setRank", function(source, identifier, rank)
    local gang = Peak.Gangs.GetPlayerGang(source)
    if not gang or not canManage(source, gang, ranks.leader) then
        return { success = false, message = "Only the leader can change ranks." }
    end
    if rank ~= "officer" and rank ~= "member" then return { success = false, message = "Invalid rank." } end
    if identifier == gang.leader then return { success = false, message = "The leader rank cannot be changed." } end

    local member = findMember(gang, identifier)
    if not member then return { success = false, message = "Member not found." } end
    member.rank = rank
    Peak.Gangs.AddActivity(gang.id, {
        type = "member",
        title = "Rank updated",
        message = ("%s is now %s."):format(member.name or "Member", rank),
    })
    saveGang(gang)
    return { success = true, gang = gang }
end)

Peak.Server.RegisterCallback("peak-sprays:gang:setOfficialMark", function(source, mark)
    local gang = Peak.Gangs.GetPlayerGang(source)
    if not gang or not canManage(source, gang, ranks.officer) then
        return { success = false, message = "You cannot set the official mark." }
    end
    if type(mark) ~= "table" then return { success = false, message = "Invalid mark data." } end
    gang.official_mark = mark
    Peak.Gangs.AddActivity(gang.id, {
        type = "mark",
        title = "Official mark updated",
        message = ("Official mark set to %s."):format(mark.name or "Unnamed mark"),
    })
    saveGang(gang)
    return { success = true, gang = gang }
end)

Peak.Server.RegisterCallback("peak-sprays:gang:getActivity", function(source)
    local gang = Peak.Gangs.GetPlayerGang(source)
    if not gang then return { success = false, message = "No gang found.", activity = {} } end
    return { success = true, activity = gang.metadata.activity or {} }
end)

Peak.Server.RegisterCallback("peak-sprays:gang:getDashboard", function(source)
    local gang = Peak.Gangs.GetPlayerGang(source)
    if not gang then
        return {
            success = true,
            gang = nil,
            permissions = { rank = nil, canInvite = false, canManage = false, canLead = false },
            summary = { activeSprays = 0, contestedSprays = 0, discoveredSprays = 0, onlineMembers = 0 },
            activity = {},
        }
    end

    local rank, rankLevel = Peak.Gangs.GetRank(source, gang)
    local activeRows = Peak.Server.ExecuteSQL("SELECT COUNT(*) AS total FROM spray_paintings WHERE gang_id = @gang_id", {
        ["@gang_id"] = gang.id,
    }) or {}
    local contestedRows = Peak.Server.ExecuteSQL("SELECT COUNT(*) AS total FROM spray_paintings WHERE gang_id = @gang_id AND status = 'contested'", {
        ["@gang_id"] = gang.id,
    }) or {}

    return {
        success = true,
        gang = gang,
        permissions = {
            rank = rank,
            canInvite = rankLevel >= ranks.officer,
            canManage = rankLevel >= ranks.officer,
            canLead = rankLevel >= ranks.leader,
        },
        summary = {
            activeSprays = activeRows[1] and tonumber(activeRows[1].total) or 0,
            contestedSprays = contestedRows[1] and tonumber(contestedRows[1].total) or 0,
            discoveredSprays = #(gang.discovered_sprays or {}),
            onlineMembers = #Peak.Gangs.GetOnlineMembers(gang.id),
        },
        activity = gang.metadata.activity or {},
    }
end)
