Peak = Peak or {}
Peak.Client = Peak.Client or {}

-- ============================================================
-- PLAYER DATA BRIDGE
-- ============================================================

--- Returns the player's full data from the active framework.
--- @return table|nil
function Peak.Client.GetPlayerData()
    local framework = Peak.Client.FrameworkName
    local obj = Peak.Client.FrameworkObject
    
    if framework == "qbcore" or framework == "qbox" then
        return obj.Functions.GetPlayerData()
    elseif framework == "esx" then
        return obj.GetPlayerData()
    end
    return nil
end

--- Returns the player's job data normalized across frameworks.
--- @return table {name, label, grade, grade_name}
function Peak.Client.GetPlayerJob()
    local data = Peak.Client.GetPlayerData()
    if not data then
        return { name = "unemployed", label = "Unemployed", grade = 0, grade_name = "" }
    end
    
    local framework = Peak.Client.FrameworkName
    if framework == "qbcore" or framework == "qbox" then
        local job = data.job
        return {
            name = job.name,
            label = job.label,
            grade = job.grade.level or 0,
            grade_name = job.grade.name or ""
        }
    elseif framework == "esx" then
        local job = data.job
        return {
            name = job.name,
            label = job.label,
            grade = job.grade,
            grade_name = job.grade_name or ""
        }
    end
    
    return { name = "unemployed", label = "Unemployed", grade = 0, grade_name = "" }
end

-- ============================================================
-- UI & INTERACTION BRIDGE
-- ============================================================

--- Displays a notification using the active subsystem.
--- @param text string Message content
--- @param type string 'success'|'error'|'info'|'warning'
--- @param duration number ms
--- @param title string Optional title
function Peak.Client.Notify(text, type, duration, title)
    type = type or "info"
    duration = duration or 5000
    
    -- Check for user override
    if Open and Open.CustomNotify then
        if Open.CustomNotify(text, type, duration) then return end
    end
    
    local system = Peak.Client.GetNotifySystem()
    if system == "ox_lib" then
        lib.notify({
            title = title or "Notification",
            description = text,
            type = type,
            duration = duration
        })
    elseif system == "qb-core" then
        local qbType = type == "info" and "primary" or (type == "warning" and "error" or type)
        Peak.Client.FrameworkObject.Functions.Notify(text, qbType, duration)
    elseif system == "esx" then
        local esxType = type == "warning" and "error" or type
        Peak.Client.FrameworkObject.ShowNotification(text, esxType, duration)
    else
        SetNotificationTextEntry("STRING")
        AddTextComponentSubstringPlayerName(text)
        DrawNotification(false, false)
    end
end

--- Displays a progress bar using the active subsystem.
--- @param label string Label text
--- @param duration number ms
--- @param settings table Animation and prop settings
--- @return boolean success Returns true if completed, false if cancelled
function Peak.Client.ProgressBar(label, duration, settings)
    settings = settings or {}
    
    if Open and Open.CustomProgressBar then
        local res = Open.CustomProgressBar(label, duration, settings)
        if res ~= nil then return res end
    end
    
    local system = Peak.Client.GetProgressSystem()
    if system == "ox_lib" then
        local options = {
            duration = duration,
            label = label,
            useWhileDead = false,
            canCancel = true,
            disable = {
                move = settings.disableMove ~= false,
                car = settings.disableCarMove ~= false,
                combat = settings.disableCombat ~= false
            }
        }
        if settings.dict and settings.anim then
            options.anim = { dict = settings.dict, clip = settings.anim }
        end
        if settings.prop then
            options.prop = {
                model = settings.prop,
                bone = settings.bone or 57005,
                pos = settings.propPos or vec3(0.0, 0.0, 0.0),
                rot = settings.propRot or vec3(0.0, 0.0, 0.0)
            }
        end
        return lib.progressBar(options)
    elseif system == "qb-core" then
        local p = promise.new()
        local anim = (settings.dict and settings.anim) and { animDict = settings.dict, anim = settings.anim } or {}
        local prop = settings.prop and { model = settings.prop, bone = settings.bone or 57005 } or {}
        
        Peak.Client.FrameworkObject.Functions.Progressbar("peak_progress_" .. Peak.Utils.RandomString(4), label, duration, settings.disableMove ~= false, settings.disableCarMove ~= false, {
            disableMovement = settings.disableMove ~= false,
            disableCarMovement = settings.disableCarMove ~= false,
            disableMouse = false,
            disableCombat = settings.disableCombat ~= false
        }, anim, prop, function() p:resolve(true) end, function() p:resolve(false) end)
        
        return Citizen.Await(p)
    else
        Wait(duration)
        return true
    end
end

--- Shows a Text UI/Floating Help Text.
--- @param text string Label content
--- @param position string Side of screen
function Peak.Client.ShowTextUI(text, position)
    position = position or "right-center"
    if GetResourceState("ox_lib") == "started" or Peak.Client.FrameworkName == "qbox" then
        lib.showTextUI(text, { position = position })
    elseif Peak.Client.FrameworkName == "qbcore" then
        exports["qb-core"]:DrawText(text, position)
    end
end

--- Hides any active Text UI.
function Peak.Client.HideTextUI()
    if GetResourceState("ox_lib") == "started" or Peak.Client.FrameworkName == "qbox" then
        lib.hideTextUI()
    elseif Peak.Client.FrameworkName == "qbcore" then
        exports["qb-core"]:HideText()
    end
end

-- ============================================================
-- AMBULANCE / DEATH BRIDGE
-- ============================================================

--- Checks if a player is currently dead/incapacitated.
--- @param playerId? number Server ID (nil for local player)
--- @return boolean
function Peak.Client.IsPlayerDead(playerId)
    if Open and Open.CustomIsPlayerDead then
        local res = Open.CustomIsPlayerDead(playerId)
        if res ~= nil then return res end
    end
    
    local system = Peak.Client.GetAmbulanceSystem()
    local exporters = {
        wasabi_ambulance_v2 = "wasabi_ambulance_v2",
        wasabi_ambulance = "wasabi_ambulance",
        qbx_medical = "qbx_medical",
        ["renewed-ambulancejob"] = "renewed-ambulancejob",
        msk_medical = "msk_medical",
        pickle_injury = "pickle_injury",
        ars_ambulancejob = "ars_ambulancejob",
        cd_ambulance = "cd_ambulance",
        ox_mdt = "ox_mdt"
    }
    
    if exporters[system] then
        local funcName = (system == "pickle_injury" and "IsDead") or (system == "cd_ambulance" and "IsPlayerDead") or "isPlayerDead"
        local ok, dead = pcall(function() return exports[system][funcName](playerId) end)
        if ok then return dead == true end
    elseif system == "qb-ambulancejob" then
        local data = Peak.Client.GetPlayerData()
        return data and data.metadata and data.metadata.isdead == true
    elseif system == "esx_ambulancejob" then
        local data = Peak.Client.GetPlayerData()
        return data and data.dead == true
    end
    
    local fw = Peak.Client.FrameworkName
    if fw == "qbcore" or fw == "qbox" then
        local data = Peak.Client.GetPlayerData()
        return data and data.metadata and data.metadata.isdead == true
    elseif fw == "esx" then
        local data = Peak.Client.GetPlayerData()
        return data and data.dead == true
    end
    
    return IsEntityDead(PlayerPedId())
end

-- ============================================================
-- EXPORTS
-- ============================================================

exports("Notify", function(...) Peak.Client.Notify(...) end)
exports("ProgressBar", function(...) return Peak.Client.ProgressBar(...) end)
exports("ShowTextUI", function(...) Peak.Client.ShowTextUI(...) end)
exports("HideTextUI", function() Peak.Client.HideTextUI() end)
exports("IsPlayerDead", function(...) return Peak.Client.IsPlayerDead(...) end)
exports("GetPlayerData", function() return Peak.Client.GetPlayerData() end)
exports("GetPlayerJob", function() return Peak.Client.GetPlayerJob() end)

-- ============================================================
-- HELPERS
-- ============================================================

--- Loads a model into memory.
--- @param model string|number
function Peak.Client.LoadModel(model)
    local hash = type(model) == "number" and model or GetHashKey(model)
    if not IsModelInCdimage(hash) then return end
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(0) end
end

--- Loads an animation dictionary into memory.
--- @param dict string
function Peak.Client.LoadAnimDict(dict)
    if not DoesAnimDictExist(dict) then return end
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do Wait(0) end
end
