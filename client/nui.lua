RegisterNUICallback("releaseMouse", function(_, cb)
    if SetSprayMouseFocus then
        SetSprayMouseFocus(false)
    else
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        if SprayState then
            SprayState._nuiMouseActive = false
        end
    end
    cb({ success = true })
end)

RegisterNUICallback("confirmSpray", function(_, cb)
    if SetSprayMouseFocus then
        SetSprayMouseFocus(false)
    else
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        if SprayState then
            SprayState._nuiMouseActive = false
        end
    end

    if SprayState and (SprayState.mode == "painting" or SprayState.mode == "erasing") then
        SprayState.pendingCancel = false
        SprayState.pendingValidate = true
    end
    cb({ success = true })
end)

RegisterNUICallback("cancelSpray", function(_, cb)
    if SetSprayMouseFocus then
        SetSprayMouseFocus(false)
    else
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        if SprayState then
            SprayState._nuiMouseActive = false
        end
    end

    if SprayState and (SprayState.mode == "selecting" or SprayState.mode == "painting" or SprayState.mode == "erasing") then
        SprayState.pendingValidate = false
        SprayState.pendingCancel = true
    end
    cb({ success = true })
end)

RegisterNUICallback("changeColor", function(data, cb)
    if SprayState and data and data.color and not SprayState.forcedColor then
        SprayState.currentColor = data.color
        if SprayState.duiObject then
            SendDuiMessage(SprayState.duiObject, json.encode({ action = "updateBrush", color = data.color }))
        end
    end
    cb({ success = true })
end)

RegisterNUICallback("changeDensity", function(data, cb)
    if SprayState and data and data.density then
        SprayState.density = SprayUtils.Clamp(tonumber(data.density) or SprayState.density, 0.0, 1.0)
    end
    cb({ success = true })
end)

RegisterNUICallback("uiExportPainting", function(_, cb)
    if SprayState and SprayState.strokeHistory then
        local result = Peak.Client.TriggerCallback("peak-sprays:exportCurrentStrokes", {
            strokeData = SprayState.strokeHistory,
            canvasWidth = SprayState.canvasWidth or Config.CanvasWidth,
            canvasHeight = SprayState.canvasHeight or Config.CanvasHeight
        })
        if result and result.code then
            SendNUIMessage({ action = "exportResult", code = result.code })
        end
        cb(result or { success = false })
        return
    end
    cb({ success = false })
end)

RegisterNUICallback("uiImportPainting", function(data, cb)
    if SprayState and SprayState.duiObject and data and data.code then
        local result = Peak.Client.TriggerCallback("peak-sprays:importPainting", data.code)
        if result and result.success and result.strokeData then
            SprayState.strokeHistory = result.strokeData
            SprayState.strokeCount = #result.strokeData
            SprayState.totalPoints = 0
            for _, stroke in ipairs(result.strokeData) do
                if type(stroke) == "table" and type(stroke.points) == "table" then
                    SprayState.totalPoints = SprayState.totalPoints + #stroke.points
                end
            end
            SendDuiMessage(SprayState.duiObject, json.encode({ action = "loadStrokes", strokes = result.strokeData }))
            SendNUIMessage({
                action = "strokeUpdate",
                strokeCount = SprayState.strokeCount,
                maxStrokes = Config.MaxStrokesPerPainting,
                canUndo = SprayState.strokeCount > 0,
                canRedo = false
            })
        end
        cb(result or { success = false })
        return
    end
    cb({ success = false })
end)

RegisterNUICallback("copyResult", function(_, cb)
    cb({ success = true })
end)

RegisterNUICallback("imageLoadFailed", function(data, cb)
    Peak.Client.Notify(data and data.message or "Image failed to load", "error", Config.NotifyDuration)
    if CancelPendingImage then
        CancelPendingImage()
    end
    cb({ success = true })
end)

RegisterNUICallback("sceneEditor:sceneData", function(data, cb)
    cb(Peak.HandleSceneEditorData(data))
end)

RegisterNUICallback("sceneEditor:saveScene", function(_, cb)
    cb(Peak.HandleSceneEditorSave())
end)

RegisterNUICallback("sceneEditor:close", function(_, cb)
    cb(Peak.HandleSceneEditorClose())
end)

RegisterNUICallback("sceneEditor:editPosition", function(_, cb)
    cb(Peak.HandleSceneEditorEditPosition())
end)

RegisterNUICallback("getLocale", function(_, cb)
    cb({ lang = "en" })
end)
