Peak = Peak or {}
ScenesHidden = false

local Creator = {
    running = false,
    placing = false,
    sceneType = "scene",
    displayData = nil,
    coords = nil,
    normal = nil,
    rotation = nil,
    renderer = nil
}

local function defaultSceneData(sceneType, text)
    local preset = Config.ScenePresets and Config.ScenePresets[sceneType == "sign" and 2 or 1] or {}
    local data = Peak.SceneUtils.Clone(preset)
    data.name = nil
    data.text = text and text ~= "" and text or (sceneType == "sign" and "NOTICE" or "This is a scene.")
    data.distance = data.distance or Config.SceneDefaultDistance
    data.closeDistance = data.closeDistance or Config.SceneDefaultCloseDistance
    data.hoursVisible = data.hoursVisible or Config.SceneDefaultHours
    data.visibility = data.visibility or "always"
    data.rotationType = data.rotationType or "rotateGround"
    return data
end

local function sendEditorAction(action, payload)
    SendNUIMessage({
        event = "sendAppEvent",
        app = "sceneEditor",
        action = action,
        payload = payload
    })
end

local function sendRootAction(action, payload)
    SendNUIMessage({
        event = "sendAppEvent",
        app = "root",
        action = action,
        payload = payload
    })
end

local function updateTargetFromRay()
    local hit, coords, _, normal = Peak.SceneUtils.GetCameraRay(Config.ScenePlacementDistance)
    if not hit then
        Creator.coords = nil
        Creator.normal = nil
        Creator.rotation = nil
        return false
    end

    local pedCoords = GetEntityCoords(PlayerPedId())
    if #(coords - pedCoords) > Config.ScenePlacementDistance then
        Creator.coords = nil
        Creator.normal = nil
        Creator.rotation = nil
        return false
    end

    Creator.coords = coords + (normal * 0.025)
    Creator.normal = normal
    Creator.rotation = Peak.SceneUtils.ComputeRotation(Creator.coords, normal, Creator.displayData and Creator.displayData.rotationType)
    return true
end

local function drawCreatorPreview()
    if not Creator.coords or not Creator.renderer then return end

    local txd, txn = Peak.SceneRenderers.Texture(Creator.renderer)
    if not txd or not txn then return end

    local rotation = Peak.SceneUtils.ResolveRenderRotation(Creator.coords, Creator.rotation)
    local scale = Config.SceneScale or 0.1
    local width = 25.0 * scale
    local height = ((Config.SceneRendererHeight or 720) / (Config.SceneRendererWidth or 1280)) * width

    DrawMarker(
        8,
        Creator.coords.x, Creator.coords.y, Creator.coords.z,
        0.0, 0.0, 0.0,
        rotation.x, rotation.y, rotation.z,
        width, height, 0.0,
        255, 255, 255, 255,
        false, false, 2, false,
        txd, txn, false
    )
end

local function cleanupCreator()
    Creator.running = false
    Creator.placing = false

    if Creator.renderer then
        Peak.SceneRenderers.DestroyRenderer(Creator.renderer)
    end

    sendEditorAction("setVisible", false)
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    Peak.Client.HideTextUI()

    Creator.sceneType = "scene"
    Creator.displayData = nil
    Creator.coords = nil
    Creator.normal = nil
    Creator.rotation = nil
    Creator.renderer = nil
end

local function creatorLoop()
    CreateThread(function()
        while Creator.running do
            Wait(0)
            if not Creator.running then break end

            if Creator.placing then
                updateTargetFromRay()
                Peak.Client.ShowTextUI(L("scene_place_help"), "bottom-center")

                if IsControlJustReleased(0, 191) then
                    Creator.placing = false
                    SetNuiFocus(true, true)
                    SetNuiFocusKeepInput(false)
                    Peak.Client.HideTextUI()
                    if not Creator.coords then
                        Peak.Client.Notify(L("scene_no_surface"), "error", Config.NotifyDuration)
                    end
                elseif IsControlJustReleased(0, 177) then
                    Peak.Client.Notify(L("scene_cancelled"), "info", Config.NotifyDuration)
                    cleanupCreator()
                    return
                end
            else
                Peak.Client.ShowTextUI(L("scene_editor_help"), "bottom-center")
            end

            drawCreatorPreview()
        end
    end)
end

function StartTextSceneCreator(sceneType, text)
    if not Config.ScenesEnabled or Creator.running then return end
    if not CanCreateScene(sceneType) then
        Peak.Client.Notify(L("scene_no_permission"), "error", Config.NotifyDuration)
        return
    end

    Creator.running = true
    Creator.placing = true
    Creator.sceneType = sceneType == "sign" and "sign" or "scene"
    Creator.displayData = defaultSceneData(Creator.sceneType, text)
    Creator.renderer = Peak.SceneRenderers.GetRenderer(true)

    if not Creator.renderer then
        Peak.Client.Notify("No scene renderer available", "error", Config.NotifyDuration)
        cleanupCreator()
        return
    end

    updateTargetFromRay()
    Peak.SceneRenderers.Send(Creator.renderer, "setSceneData", Creator.displayData)
    Peak.SceneRenderers.Send(Creator.renderer, "setVisible", true)
    Peak.SceneRenderers.Send(Creator.renderer, "setEye", false)

    local history = Peak.Client.TriggerCallback("peak-sprays:getTextSceneHistory") or {}
    sendRootAction("setConfig", { accentColor = Config.SceneAccentColor })
    sendEditorAction("setSceneType", Creator.sceneType)
    sendEditorAction("setHistory", history)
    sendEditorAction("setPresets", Config.ScenePresets or {})
    sendEditorAction("newScene", Creator.displayData)
    sendEditorAction("setVisible", true)

    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    Peak.Client.Notify(L("scene_started"), "success", Config.NotifyDuration)
    creatorLoop()
end

RegisterNetEvent("peak-sprays:cl:openTextSceneCreator", function(sceneType, text)
    StartTextSceneCreator(sceneType, text)
end)

if Config.SceneUseCommand then
    RegisterCommand(Config.SceneCommandName, function(_, args, raw)
        local text = raw:gsub("^" .. Config.SceneCommandName .. "%s*", "")
        StartTextSceneCreator("scene", text)
    end, false)

    RegisterCommand(Config.SignCommandName, function(_, args, raw)
        local text = raw:gsub("^" .. Config.SignCommandName .. "%s*", "")
        StartTextSceneCreator("sign", text)
    end, false)

    RegisterCommand(Config.SceneHideCommandName, function()
        ScenesHidden = not ScenesHidden
        SetResourceKvpInt("peak_text_scenes_hidden", ScenesHidden and 1 or 0)
        Peak.Client.Notify(ScenesHidden and L("scene_hidden_on") or L("scene_hidden_off"), "info", Config.NotifyDuration)
    end, false)

    RegisterCommand(Config.SceneDeleteCommandName, function()
        DeleteNearestTextScene()
    end, false)
end

function DeleteNearestTextScene()
    if not CanDeleteScene() then
        Peak.Client.Notify(L("scene_delete_denied"), "error", Config.NotifyDuration)
        return
    end

    local pedCoords = GetEntityCoords(PlayerPedId())
    local closest, closestDist = nil, 999999.0

    for _, scene in pairs(Peak.TextScenes) do
        local dist = #(pedCoords - scene.coords)
        if dist < closestDist then
            closest = scene
            closestDist = dist
        end
    end

    if not closest or closestDist > 5.0 then
        Peak.Client.Notify(L("scene_not_found"), "error", Config.NotifyDuration)
        return
    end

    local result = Peak.Client.TriggerCallback("peak-sprays:deleteTextScene", closest.id)
    if result and result.success then
        Peak.Client.Notify(L("scene_deleted"), "success", Config.NotifyDuration)
    else
        Peak.Client.Notify(result and result.error or L("scene_delete_denied"), "error", Config.NotifyDuration)
    end
end

function Peak.HandleSceneEditorData(data)
    if not Creator.running then return false end
    Creator.displayData = data or Creator.displayData
    Creator.rotation = Creator.coords and Peak.SceneUtils.ComputeRotation(Creator.coords, Creator.normal, Creator.displayData.rotationType) or nil
    Peak.SceneRenderers.Send(Creator.renderer, "setSceneData", Creator.displayData)
    return true
end

function Peak.HandleSceneEditorSave()
    if not Creator.running then
        return { success = false, error = L("scene_cancelled") }
    end

    if not Creator.coords then
        return { success = false, error = L("scene_no_surface") }
    end

    local payload = {
        sceneType = Creator.sceneType,
        displayData = Creator.displayData,
        coords = Peak.SceneUtils.VecToTable(Creator.coords),
        rotation = Peak.SceneUtils.VecToTable(Creator.rotation)
    }

    local result = Peak.Client.TriggerCallback("peak-sprays:createTextScene", payload)
    if result and result.success then
        Peak.Client.Notify(L("scene_saved"), "success", Config.NotifyDuration)
        OnTextSceneCreated(result.scene)
        cleanupCreator()
        return result
    end

    return result or { success = false, error = "Save failed" }
end

function Peak.HandleSceneEditorClose()
    if Creator.running then
        Peak.Client.Notify(L("scene_cancelled"), "info", Config.NotifyDuration)
        cleanupCreator()
    end
    return "ok"
end

function Peak.HandleSceneEditorEditPosition()
    if not Creator.running then return "ok" end
    Creator.placing = true
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    return "ok"
end

CreateThread(function()
    Wait(2000)
    ScenesHidden = GetResourceKvpInt("peak_text_scenes_hidden") == 1

    while not Peak.Client or not Peak.Client.Ready do Wait(250) end
    local scenes = Peak.Client.TriggerCallback("peak-sprays:getTextScenes") or {}
    for _, scene in pairs(scenes) do
        Peak.CreateTextScene(scene)
    end
    EnsureTextSceneRenderingThread()
end)
