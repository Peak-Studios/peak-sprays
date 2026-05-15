Peak = Peak or {}
Peak.Phone = Peak.Phone or {}

local phoneDrivers = {
    {
        resource = "lb-phone",
        send = function(src, title, message)
            return exports["lb-phone"]:SendMail(src, { sender = "Territory Watch", subject = title, message = message })
        end
    },
    {
        resource = "qb-phone",
        send = function(src, title, message)
            TriggerClientEvent("qb-phone:client:CustomNotification", src, title, message, "fas fa-spray-can", "#b91c1c", 8000)
            TriggerClientEvent("qb-phone:client:NewMailNotify", src, { sender = "Territory Watch", subject = title, message = message })
            return true
        end
    },
    {
        resource = "npwd",
        send = function(src, title, message)
            TriggerClientEvent("npwd:client:sendNotification", src, {
                app = "MESSAGES",
                title = title,
                content = message,
            })
            return true
        end
    },
    {
        resource = "gksphone",
        send = function(src, title, message)
            TriggerClientEvent("gksphone:notifi", src, { title = title, message = message, img = "/html/static/img/icons/mail.png" })
            return true
        end
    },
    {
        resource = "17mov_phone",
        send = function(src, title, message)
            TriggerClientEvent("17mov_phone:client:notification", src, title, message)
            return true
        end
    },
}

local activeDriver

local function DetectPhone()
    for _, driver in ipairs(phoneDrivers) do
        if GetResourceState(driver.resource) == "started" then
            activeDriver = driver
            Peak.Utils.Debug("Phone detected:", driver.resource)
            return
        end
    end
    activeDriver = nil
end

CreateThread(function()
    Wait(1500)
    DetectPhone()
end)

function Peak.Phone.GetActiveDriver()
    if activeDriver and GetResourceState(activeDriver.resource) == "started" then
        return activeDriver.resource
    end
    DetectPhone()
    return activeDriver and activeDriver.resource or "native"
end

function Peak.Phone.SendGangNotification(src, title, message)
    if not src then return false end
    if not activeDriver or GetResourceState(activeDriver.resource) ~= "started" then
        DetectPhone()
    end

    if activeDriver then
        local ok, sent = pcall(activeDriver.send, src, title, message)
        if ok and sent ~= false then return true end
        Peak.Utils.Warn("Phone notification failed for", activeDriver.resource, sent)
    end

    TriggerClientEvent("peak-sprays:cl:gangAlert", src, { title = title, message = message })
    return true
end

function Peak.Phone.SendGangBroadcast(gangId, title, message)
    if not Peak.Gangs or not Peak.Gangs.GetOnlineMembers then return end
    for _, src in ipairs(Peak.Gangs.GetOnlineMembers(gangId)) do
        Peak.Phone.SendGangNotification(src, title, message)
    end
end
