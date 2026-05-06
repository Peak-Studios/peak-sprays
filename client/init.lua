Peak = Peak or {}
Peak.Client = Peak.Client or {}
Peak.Client.Framework = nil
Peak.Client.FrameworkName = nil
Peak.Client.FrameworkObject = nil
Peak.Client.FrameworkShared = nil
Peak.Client.Ready = false
Peak.Client.PendingCallbacks = {}
Peak.Client.CallbackId = 0

local notifySystem = nil
local targetSystem = nil
local progressSystem = nil
local ambulanceSystem = nil

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
    Peak.Client.FrameworkName = GetFrameworkName()
    local framework = Peak.Client.FrameworkName
    
    if framework == "qbcore" then
        Peak.Client.FrameworkObject = exports["qb-core"]:GetCoreObject()
        Peak.Client.FrameworkShared = Peak.Client.FrameworkObject.Shared
    elseif framework == "qbox" then
        local ok, obj = pcall(function() return exports.qbx_core:GetCoreObject() end)
        if ok and obj then
            Peak.Client.FrameworkObject = obj
            Peak.Client.FrameworkShared = obj.Shared
        else
            -- Fallback for older QBox versions
            local qbx = exports.qbx_core
            Peak.Client.FrameworkObject = {
                Functions = setmetatable({}, {
                    __index = function(_, key)
                        if key == "GetPlayerData" then
                            return function()
                                if rawget(_G, "QBX") and QBX.PlayerData then
                                    return QBX.PlayerData
                                end
                                local ok2, data = pcall(qbx.GetPlayerData, qbx)
                                return (ok2 and data) or {}
                            end
                        end
                        return function(...)
                            return qbx[key](qbx, ...)
                        end
                    end
                })
            }
            Peak.Client.FrameworkShared = setmetatable({}, {
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
        end
    elseif framework == "esx" then
        Peak.Client.FrameworkObject = exports.es_extended:getSharedObject()
    end
    
    Peak.Client.Ready = true
    Peak.Utils.Debug("Client framework initialized:", framework)
end

--- Initializes external subsystems (Notify, Target, Progress, Ambulance).
local function InitializeSubsystems()
    -- Notify
    if Config.Notify == "auto" then
        if GetResourceState("ox_lib") == "started" then
            notifySystem = "ox_lib"
        elseif GetResourceState("qb-core") == "started" then
            notifySystem = "qb-core"
        elseif GetResourceState("es_extended") == "started" then
            notifySystem = "esx"
        else
            notifySystem = "native"
        end
    else
        notifySystem = Config.Notify
    end

    -- Target
    if Config.Target == "auto" then
        if GetResourceState("ox_target") == "started" then
            targetSystem = "ox_target"
        elseif GetResourceState("qb-target") == "started" then
            targetSystem = "qb-target"
        end
    else
        targetSystem = Config.Target
    end

    -- Progress
    if Config.Progress == "auto" then
        if GetResourceState("ox_lib") == "started" then
            progressSystem = "ox_lib"
        elseif GetResourceState("progressbar") == "started" then
            progressSystem = "qb-core"
        else
            progressSystem = "wait"
        end
    else
        progressSystem = Config.Progress
    end

    -- Ambulance
    if Config.Ambulance == "auto" then
        local systems = {
            "wasabi_ambulance_v2", "wasabi_ambulance", "qbx_medical", "renewed-ambulancejob",
            "msk_medical", "pickle_injury", "ars_ambulancejob", "cd_ambulance", "ox_mdt",
            "qb-ambulancejob", "esx_ambulancejob"
        }
        for _, s in ipairs(systems) do
            if GetResourceState(s) == "started" then
                ambulanceSystem = s
                break
            end
        end
        ambulanceSystem = ambulanceSystem or "framework"
    elseif Config.Ambulance == "custom" then
        ambulanceSystem = "custom"
    else
        ambulanceSystem = Config.Ambulance
    end

    Peak.Utils.Debug("Subsystems initialized - Notify:", notifySystem, "Target:", targetSystem, "Progress:", progressSystem, "Ambulance:", ambulanceSystem)
end

-- ============================================================
-- CALLBACK HANDLING
-- ============================================================

--- Triggers a server-side callback and awaits the response.
--- @param name string Callback name
--- @param ... any Arguments to pass
--- @return any Response data
function Peak.Client.TriggerCallback(name, ...)
    local p = promise.new()
    Peak.Client.CallbackId = Peak.Client.CallbackId + 1
    local id = Peak.Client.CallbackId
    
    Peak.Client.PendingCallbacks[id] = p
    TriggerServerEvent("peak-sprays:server:triggerCallback", id, name, ...)
    
    -- Timeout handling (15s)
    SetTimeout(15000, function()
        if Peak.Client.PendingCallbacks[id] then
            Peak.Client.PendingCallbacks[id]:reject("Callback timeout: " .. name)
            Peak.Client.PendingCallbacks[id] = nil
        end
    end)
    
    return Citizen.Await(p)
end

RegisterNetEvent("peak-sprays:client:callbackResponse", function(id, data)
    if Peak.Client.PendingCallbacks[id] then
        Peak.Client.PendingCallbacks[id]:resolve(data)
        Peak.Client.PendingCallbacks[id] = nil
    end
end)

-- ============================================================
-- GETTERS
-- ============================================================

function Peak.Client.GetNotifySystem() return notifySystem end
function Peak.Client.GetTargetSystem() return targetSystem end
function Peak.Client.GetProgressSystem() return progressSystem end
function Peak.Client.GetAmbulanceSystem() return ambulanceSystem end

-- ============================================================
-- EXPORTS
-- ============================================================

exports("TriggerCallback", function(name, ...)
    return Peak.Client.TriggerCallback(name, ...)
end)

exports("GetClientFrameworkName", function()
    return Peak.Client.FrameworkName
end)

exports("IsClientReady", function()
    return Peak.Client.Ready
end)

-- ============================================================
-- STARTUP
-- ============================================================

CreateThread(function()
    Wait(500)
    InitializeFramework()
    InitializeSubsystems()
end)
