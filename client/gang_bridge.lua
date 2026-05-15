Peak = Peak or {}
Peak.ClientGang = {
    gang = nil,
    phone = "native",
}

local function refreshGang()
    local result = Peak.Client.TriggerCallback("peak-sprays:gang:getSelf")
    if result then
        Peak.ClientGang.gang = result.gang
        Peak.ClientGang.phone = result.phone or "native"
    end
    return Peak.ClientGang
end

local function respond(cb, result)
    if type(result) == "table" and result.success ~= nil then
        cb(result)
        return
    end

    cb({
        success = true,
        data = result,
    })
end

CreateThread(function()
    while not Peak.Client or not Peak.Client.Ready do Wait(500) end
    refreshGang()
end)

RegisterNetEvent("peak-sprays:cl:gangUpdated", function(gang)
    Peak.ClientGang.gang = gang
    SendNUIMessage({ action = "gangData", gang = gang })
end)

RegisterNetEvent("peak-sprays:cl:gangAlert", function(alert)
    Peak.Client.Notify(alert.message or "Gang alert", "warning", Config.NotifyDuration, alert.title or "Gang")
    SendNUIMessage({ action = "gangAlert", alert = alert })
end)

RegisterCommand(Config.GangLaptopCommand, function()
    local state = refreshGang()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openLaptop",
        gang = state.gang,
        phone = state.phone,
    })
end, false)

RegisterNUICallback("laptop:close", function(_, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "closeLaptop" })
    cb({ success = true })
end)

RegisterNUICallback("gang:create", function(data, cb)
    respond(cb, Peak.Client.TriggerCallback("peak-sprays:gang:create", data and data.name))
end)

RegisterNUICallback("gang:addMember", function(data, cb)
    respond(cb, Peak.Client.TriggerCallback("peak-sprays:gang:addMember", data and data.targetId))
end)

RegisterNUICallback("gang:kick", function(data, cb)
    respond(cb, Peak.Client.TriggerCallback("peak-sprays:gang:kick", data and data.identifier))
end)

RegisterNUICallback("gang:setRank", function(data, cb)
    respond(cb, Peak.Client.TriggerCallback("peak-sprays:gang:setRank", data and data.identifier, data and data.rank))
end)

RegisterNUICallback("gang:setOfficialMark", function(data, cb)
    respond(cb, Peak.Client.TriggerCallback("peak-sprays:gang:setOfficialMark", data and data.mark))
end)

RegisterNUICallback("gang:getAll", function(_, cb)
    respond(cb, Peak.Client.TriggerCallback("peak-sprays:gang:getAll") or {})
end)

RegisterNUICallback("gang:getDashboard", function(_, cb)
    respond(cb, Peak.Client.TriggerCallback("peak-sprays:gang:getDashboard"))
end)

RegisterNUICallback("gang:getActivity", function(_, cb)
    respond(cb, Peak.Client.TriggerCallback("peak-sprays:gang:getActivity"))
end)

RegisterNUICallback("territory:getMap", function(_, cb)
    respond(cb, Peak.Client.TriggerCallback("peak-sprays:territory:getMap") or {})
end)

RegisterNUICallback("territory:getSummary", function(_, cb)
    respond(cb, Peak.Client.TriggerCallback("peak-sprays:territory:getSummary") or {})
end)

RegisterNUICallback("territory:toggleDiscovered", function(data, cb)
    respond(cb, Peak.Client.TriggerCallback("peak-sprays:territory:toggleDiscovered", data and data.sprayId))
end)

RegisterNUICallback("territory:toggleContested", function(_, cb)
    respond(cb, Peak.Client.TriggerCallback("peak-sprays:territory:toggleContested"))
end)

exports("GetGangData", function()
    return Peak.ClientGang.gang
end)
