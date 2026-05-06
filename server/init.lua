Peak = Peak or {}
Peak.Server = Peak.Server or {}
Peak.Server.Framework = nil
Peak.Server.FrameworkName = nil
Peak.Server.FrameworkObject = nil
Peak.Server.FrameworkShared = nil
Peak.Server.Callbacks = {}
Peak.Server.Ready = false

local inventorySystem = nil
local sqlDriver = nil

-- ============================================================
-- INITIALIZATION
-- ============================================================

--- Detects the currently running framework.
--- @return string frameworkName
local function GetFrameworkName()
    if Config.Framework ~= "auto" then
        return Config.Framework
    end
    
    if GetResourceState("qb-core") == "started" then
        return "qbcore"
    elseif GetResourceState("qbx_core") == "started" then
        return "qbox"
    elseif GetResourceState("es_extended") == "started" then
        return "esx"
    elseif GetResourceState("ox_core") == "started" then
        return "ox"
    elseif GetResourceState("vrp") == "started" then
        return "vrp"
    end
    
    return "standalone"
end

--- Initializes the framework object and shared data.
local function InitializeFramework()
    Peak.Server.FrameworkName = GetFrameworkName()
    local framework = Peak.Server.FrameworkName
    
    if framework == "qbcore" then
        Peak.Server.FrameworkObject = exports["qb-core"]:GetCoreObject()
        Peak.Server.FrameworkShared = Peak.Server.FrameworkObject.Shared
        Peak.Utils.print("Framework detected: ^5QBCore^0")
    elseif framework == "qbox" then
        local ok, obj = pcall(function() return exports.qbx_core:GetCoreObject() end)
        if ok and obj then
            Peak.Server.FrameworkObject = obj
            Peak.Server.FrameworkShared = obj.Shared
            Peak.Utils.print("Framework detected: ^5QBox (Legacy)^0")
        else
            local qbx = exports.qbx_core
            Peak.Server.FrameworkObject = {
                Functions = setmetatable({}, {
                    __index = function(_, key)
                        return function(...) return qbx[key](qbx, ...) end
                    end
                })
            }
            Peak.Server.FrameworkShared = setmetatable({}, {
                __index = function(_, key)
                    local map = {
                        Jobs = "GetJobs",
                        Gangs = "GetGangs",
                        Vehicles = "GetVehiclesByName",
                        Weapons = "GetWeapons",
                        Locations = "GetLocations"
                    }
                    if map[key] then
                        local ok2, data = pcall(qbx[map[key]], qbx)
                        if ok2 then return data end
                    end
                    if key == "Items" and GetResourceState("ox_inventory") == "started" then
                        local ok2, data = pcall(function() return exports.ox_inventory:Items() end)
                        if ok2 then return data end
                    end
                    return nil
                end
            })
            Peak.Utils.print("Framework detected: ^5QBox^0")
        end
    elseif framework == "esx" then
        Peak.Server.FrameworkObject = exports.es_extended:getSharedObject()
        Peak.Utils.print("Framework detected: ^5ESX^0")
    elseif framework == "ox" then
        Peak.Utils.print("Framework detected: ^5OX Core^0")
    elseif framework == "vrp" then
        Peak.Server.FrameworkObject = exports.vrp:getInterface()
        Peak.Utils.print("Framework detected: ^5vRP^0")
    else
        Peak.Utils.Warn("No framework detected. Running in standalone mode.")
    end
    
    Peak.Server.Ready = true
end

--- Initializes the inventory system.
local function InitializeInventory()
    if Config.Inventory ~= "auto" then
        inventorySystem = Config.Inventory
        return
    end
    
    local systems = {"ox_inventory", "qb-inventory", "qs-inventory", "ps-inventory", "codem-inventory", "gfx-inventory"}
    for _, s in ipairs(systems) do
        if GetResourceState(s) == "started" then
            inventorySystem = s
            Peak.Utils.Debug("Inventory detected:", s)
            return
        end
    end
end

--- Initializes the SQL driver.
local function InitializeSQLDriver()
    if Config.SQLDriver ~= "auto" then
        sqlDriver = Config.SQLDriver
        return
    end
    
    if GetResourceState("oxmysql") == "started" then
        sqlDriver = "oxmysql"
    elseif GetResourceState("ghmattimysql") == "started" then
        sqlDriver = "ghmattimysql"
    elseif GetResourceState("mysql-async") == "started" then
        sqlDriver = "mysql-async"
    else
        sqlDriver = "oxmysql"
    end
    
    Peak.Utils.Debug("SQL driver:", sqlDriver)
end

-- ============================================================
-- CALLBACK HANDLING
-- ============================================================

--- Registers a server-side callback.
--- @param name string Callback name
--- @param cb function Callback function
function Peak.Server.RegisterCallback(name, cb)
    Peak.Server.Callbacks[name] = cb
    Peak.Utils.Debug("Callback registered:", name)
end

RegisterNetEvent("peak-sprays:server:triggerCallback", function(id, name, ...)
    local src = source
    local cb = Peak.Server.Callbacks[name]
    
    if not cb then
        Peak.Utils.Warn("Callback not found:", name)
        TriggerClientEvent("peak-sprays:client:callbackResponse", src, id, nil)
        return
    end
    
    local ok, res = pcall(cb, src, ...)
    if ok then
        TriggerClientEvent("peak-sprays:client:callbackResponse", src, id, res)
    else
        Peak.Utils.Warn("Callback error [" .. name .. "]:", res)
        TriggerClientEvent("peak-sprays:client:callbackResponse", src, id, nil)
    end
end)

-- ============================================================
-- VERSION CHECKER
-- ============================================================

--- Sends a Discord embed webhook payload.
--- @param url string
--- @param title string
--- @param description string
--- @param color number
--- @param fields table|nil
--- @param footer string|nil
function Peak.Server.SendDiscordWebhook(url, title, description, color, fields, footer)
    if not url or url == "" then return end

    local payload = {
        embeds = {
            {
                title = title,
                description = description,
                color = color or 3447003,
                fields = fields or {},
                footer = footer and { text = footer } or nil
            }
        }
    }

    PerformHttpRequest(url, function() end, "POST", json.encode(payload), {
        ["Content-Type"] = "application/json"
    })
end

local function StartVersionChecker()
    if not Config.EnableVersionChecker or not Config.VersionURL or Config.VersionURL == "" then return end
    
    PerformHttpRequest(Config.VersionURL, function(status, body)
        if status ~= 200 or not body then
            Peak.Utils.Warn("Failed to fetch version data (HTTP " .. tostring(status) .. ")")
            return
        end
        
        local data = json.decode(body)
        if not data then return end
        
        local resourceName = GetCurrentResourceName()
        local info = data[resourceName]
        if not info then return end
        
        local currentVersion = GetResourceMetadata(resourceName, "version", 0)
        if currentVersion then
            if currentVersion == info.version then
                Peak.Utils.print("^5" .. resourceName .. "^0 is ^2up to date^0 (v" .. currentVersion .. ")")
            else
                Peak.Utils.Warn("^5" .. resourceName .. "^0 is ^1outdated^0! Current: ^1" .. currentVersion .. "^0 | Latest: ^2" .. info.version .. "^0")
            end
        end
    end, "GET")
end

-- ============================================================
-- EXPORTS
-- ============================================================

exports("GetFramework", function() return Peak.Server.FrameworkObject end)
exports("GetFrameworkName", function() return Peak.Server.FrameworkName end)
exports("IsReady", function() return Peak.Server.Ready end)
exports("RegisterCallback", function(...) Peak.Server.RegisterCallback(...) end)

-- ============================================================
-- STARTUP
-- ============================================================

CreateThread(function()
    Wait(100)
    InitializeFramework()
    InitializeInventory()
    InitializeSQLDriver()
    
    Peak.Utils.print("Peak Core initialized successfully. Framework: ^5" .. Peak.Server.FrameworkName .. "^0")
    
    Wait(5000)
    StartVersionChecker()
end)
