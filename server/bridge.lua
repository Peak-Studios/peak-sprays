Peak = Peak or {}
Peak.Server = Peak.Server or {}
Peak.Server.UsableItems = {}

-- ============================================================
-- PLAYER INFO BRIDGE
-- ============================================================

--- Returns the player's primary identifier.
--- @param src number Player source
--- @return string|nil
function Peak.Server.GetIdentifier(src)
    local fw = Peak.Server.FrameworkName
    local obj = Peak.Server.FrameworkObject
    
    if fw == "qbcore" or fw == "qbox" then
        local player = obj.Functions.GetPlayer(src)
        return player and player.PlayerData.citizenid
    elseif fw == "esx" then
        local player = obj.GetPlayerFromId(src)
        return player and player.identifier
    end
    return GetPlayerIdentifier(src, 0)
end

--- Returns the player's name.
--- @param src number Player source
--- @return string
function Peak.Server.GetPlayerName(src)
    local fw = Peak.Server.FrameworkName
    local obj = Peak.Server.FrameworkObject
    
    if fw == "qbcore" or fw == "qbox" then
        local player = obj.Functions.GetPlayer(src)
        if player then
            return player.PlayerData.charinfo.firstname .. " " .. player.PlayerData.charinfo.lastname
        end
    elseif fw == "esx" then
        local player = obj.GetPlayerFromId(src)
        if player then return player.getName() end
    end
    return GetPlayerName(src)
end

-- ============================================================
-- MONEY BRIDGE
-- ============================================================

--- Adds money to a player's account.
--- @param source number
--- @param amount number
--- @param moneyType string 'cash'|'bank'
--- @return boolean
function Peak.Server.AddMoney(source, amount, moneyType)
    moneyType = moneyType or Config.DefaultMoneyType
    
    if Config.Banking == "custom" then
        local res = Open.AddMoney(source, amount, moneyType)
        if res ~= nil then return res end
    end
    
    local fw = Peak.Server.FrameworkName
    local obj = Peak.Server.FrameworkObject
    if fw == "qbcore" or fw == "qbox" then
        local player = obj.Functions.GetPlayer(source)
        if player then
            return player.Functions.AddMoney(moneyType, amount, "peak-sprays")
        end
    elseif fw == "esx" then
        local player = obj.GetPlayerFromId(source)
        if player then
            local account = (moneyType == "cash") and "money" or moneyType
            player.addAccountMoney(account, amount, "peak-sprays")
            return true
        end
    end
    return false
end

--- Removes money from a player's account.
--- @param source number
--- @param amount number
--- @param moneyType string 'cash'|'bank'
--- @return boolean
function Peak.Server.RemoveMoney(source, amount, moneyType)
    moneyType = moneyType or Config.DefaultMoneyType
    
    if Config.Banking == "custom" then
        local res = Open.RemoveMoney(source, amount, moneyType)
        if res ~= nil then return res end
    end
    
    local fw = Peak.Server.FrameworkName
    local obj = Peak.Server.FrameworkObject
    if fw == "qbcore" or fw == "qbox" then
        local player = obj.Functions.GetPlayer(source)
        if player then
            return player.Functions.RemoveMoney(moneyType, amount, "peak-sprays")
        end
    elseif fw == "esx" then
        local player = obj.GetPlayerFromId(source)
        if player then
            local account = (moneyType == "cash") and "money" or moneyType
            player.removeAccountMoney(account, amount, "peak-sprays")
            return true
        end
    end
    return false
end

-- ============================================================
-- INVENTORY BRIDGE
-- ============================================================

--- Removes an item from a player's inventory.
--- @param source number
--- @param item string
--- @param count number
--- @return boolean
function Peak.Server.RemoveItem(source, item, count)
    local fw = Peak.Server.FrameworkName
    local obj = Peak.Server.FrameworkObject
    
    if fw == "qbcore" or fw == "qbox" then
        local player = obj.Functions.GetPlayer(source)
        if player then
            return player.Functions.RemoveItem(item, count)
        end
    elseif fw == "esx" then
        local player = obj.GetPlayerFromId(source)
        if player then
            player.removeInventoryItem(item, count)
            return true
        end
    end
    
    if GetResourceState("ox_inventory") == "started" then
        return exports.ox_inventory:RemoveItem(source, item, count)
    end
    
    return false
end

--- Checks if a player has a certain amount of an item.
--- @param source number
--- @param item string
--- @param count number
--- @return boolean
function Peak.Server.HasItem(source, item, count)
    count = count or 1
    local fw = Peak.Server.FrameworkName
    local obj = Peak.Server.FrameworkObject
    local actualCount = 0
    
    if fw == "qbcore" or fw == "qbox" then
        local player = obj.Functions.GetPlayer(source)
        if player then
            local itemData = player.Functions.GetItemByName(item)
            actualCount = itemData and (itemData.amount or 0) or 0
        end
    elseif fw == "esx" then
        local player = obj.GetPlayerFromId(source)
        if player then
            local itemData = player.getInventoryItem(item)
            actualCount = itemData and (itemData.count or 0) or 0
        end
    end
    
    if actualCount < count and GetResourceState("ox_inventory") == "started" then
        actualCount = exports.ox_inventory:GetItemCount(source, item) or 0
    end
    
    return actualCount >= count
end

--- Registers a usable item handler normalized across frameworks.
--- @param item string
--- @param cb function
function Peak.Server.RegisterUsableItem(item, cb)
    Peak.Server.UsableItems[item] = cb
    local fw = Peak.Server.FrameworkName
    local obj = Peak.Server.FrameworkObject
    
    local onUse = function(source)
        local callback = Peak.Server.UsableItems[item]
        if callback then callback(source, item) end
    end
    
    -- Try Ox Inventory first
    if GetResourceState("ox_inventory") == "started" then
        exports.ox_inventory:RegisterUsableItem(item, function(source) onUse(source) end)
        return
    end
    
    -- Framework fallbacks
    if fw == "qbox" then
        exports.qbx_core:CreateUseableItem(item, function(source) onUse(source) end)
    elseif fw == "qbcore" then
        obj.Functions.CreateUseableItem(item, function(source) onUse(source) end)
    elseif fw == "esx" then
        obj.RegisterUsableItem(item, function(source) onUse(source) end)
    end
end

-- ============================================================
-- UTILS
-- ============================================================

--- Checks if a player is an admin.
--- @param src number
--- @return boolean
function Peak.Server.IsAdmin(src)
    if IsPlayerAceAllowed(src, Config.AdminAce) then return true end
    
    local fw = Peak.Server.FrameworkName
    if fw == "qbcore" or fw == "qbox" then
        return Peak.Server.FrameworkObject.Functions.HasPermission(src, "admin") or Peak.Server.FrameworkObject.Functions.HasPermission(src, "god")
    elseif fw == "esx" then
        local player = Peak.Server.FrameworkObject.GetPlayerFromId(src)
        if player then
            local group = player.getGroup()
            for _, g in ipairs(Config.AdminGroups) do
                if group == g then return true end
            end
        end
    end
    return false
end

-- ============================================================
-- EXPORTS
-- ============================================================

exports("IsAdmin", function(src) return Peak.Server.IsAdmin(src) end)
exports("HasItem", function(...) return Peak.Server.HasItem(...) end)
exports("RemoveItem", function(...) return Peak.Server.RemoveItem(...) end)
exports("RegisterUsableItem", function(...) Peak.Server.RegisterUsableItem(...) end)
