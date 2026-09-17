Peak = Peak or {}
Peak.Studio = Peak.Studio or {}

--- Opens the Graffiti Studio UI
function Peak.Studio.Open(step, composition)
    if not CanSpray() then
        Peak.Client.Notify(L("spray_denied") or "You cannot spray right now", "error", Config.NotifyDuration)
        return
    end

    local library = Peak.Client.TriggerCallback("peak-sprays:getDesignsLibrary") or {}
    SendNUIMessage({
        action = "openStudio",
        step = step or "library",
        composition = composition
    })
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
end

--- Closes the Graffiti Studio UI
function Peak.Studio.Close()
    SendNUIMessage({ action = "closeStudio" })
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end

-- Register command for Studio
RegisterCommand(Config.StudioCommandName or "spraystudio", function()
    Peak.Studio.Open("library")
end, false)

-- Broadcast event from server when an official gang template is published
RegisterNetEvent("peak-sprays:cl:gangTemplateUpdated", function(data)
    Peak.Client.Notify(("New official gang tag published for %s: %s"):format(data.gang or "Crew", data.title or "Tag"), "info", 5000)
end)
