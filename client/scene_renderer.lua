Peak = Peak or {}
Peak.TextScenes = Peak.TextScenes or {}
Peak.SceneRenderers = Peak.SceneRenderers or {}

local availableRenderers = {}
local loadedDuis = {}
local pendingReady = {}
local renderingThreadActive = false

for i = 1, Config.SceneMaxActiveRenderers do
    availableRenderers[#availableRenderers + 1] = "peak_scene_renderer_" .. i
end

local function rendererUrl(rendererName)
    return ("nui://%s/ui/dist/scene.html?renderer=%s"):format(GetCurrentResourceName(), rendererName)
end

local function waitForRendererReady(rendererName)
    local timeout = GetGameTimer() + 5000
    while loadedDuis[rendererName] and not loadedDuis[rendererName].ready and GetGameTimer() < timeout do
        Wait(25)
    end
    return loadedDuis[rendererName] and loadedDuis[rendererName].ready
end

function Peak.SceneRenderers.GetRenderer(isCreator)
    local rendererName = isCreator and "creator" or table.remove(availableRenderers, #availableRenderers)
    if not rendererName then return nil end

    if loadedDuis[rendererName] then
        waitForRendererReady(rendererName)
        return rendererName
    end

    local width = Config.SceneRendererWidth or 1280
    local height = Config.SceneRendererHeight or 720
    local duiObj = CreateDui(rendererUrl(rendererName), width, height)

    local timeout = GetGameTimer() + 5000
    while not IsDuiAvailable(duiObj) and GetGameTimer() < timeout do
        Wait(25)
    end

    local txdName = "peak_scene_txd_" .. rendererName
    local txnName = "peak_scene_txn_" .. rendererName
    local txdObj = CreateRuntimeTxd(txdName)
    local duiHandle = GetDuiHandle(duiObj)
    CreateRuntimeTextureFromDuiHandle(txdObj, txnName, duiHandle)

    loadedDuis[rendererName] = {
        obj = duiObj,
        txd = txdName,
        txn = txnName,
        ready = pendingReady[rendererName] == true
    }
    pendingReady[rendererName] = nil

    waitForRendererReady(rendererName)
    return rendererName
end

RegisterNUICallback("sceneDui:ready", function(data, cb)
    local rendererName = data and data.renderer
    if rendererName and loadedDuis[rendererName] then
        loadedDuis[rendererName].ready = true
    elseif rendererName then
        pendingReady[rendererName] = true
    end
    cb("ok")
end)

function Peak.SceneRenderers.ReleaseRenderer(rendererName)
    if not rendererName or rendererName == "creator" then return end
    availableRenderers[#availableRenderers + 1] = rendererName
end

function Peak.SceneRenderers.DestroyRenderer(rendererName)
    local renderer = loadedDuis[rendererName]
    if renderer and renderer.obj then
        DestroyDui(renderer.obj)
    end
    loadedDuis[rendererName] = nil
end

function Peak.SceneRenderers.Send(rendererName, action, payload)
    local renderer = loadedDuis[rendererName]
    if not renderer then return end
    SendDuiMessage(renderer.obj, json.encode({
        action = action,
        payload = payload
    }))
end

function Peak.SceneRenderers.Texture(rendererName)
    local renderer = loadedDuis[rendererName]
    if not renderer then return nil, nil end
    return renderer.txd, renderer.txn
end

local Scene = {}
Scene.__index = Scene

local function sceneCoords(scene)
    return scene.coords
end

function Peak.CreateTextScene(data)
    if not data or not data.id then return nil end

    local self = setmetatable({}, Scene)
    self.id = data.id
    self.identifier = data.identifier
    self.playerName = data.playerName
    self.sceneType = data.sceneType or "scene"
    self.displayData = data.displayData or {}
    self.coords = Peak.SceneUtils.TableToVec(data.coords) or vector3(0.0, 0.0, 0.0)
    self.rotation = Peak.SceneUtils.TableToVec(data.rotation)
    self.isStaff = data.isStaff
    self.renderer = nil
    self.isRendered = false
    self.revealed = false
    self.isClose = false
    self.createdAt = data.createdAt
    self.expiresAt = data.expiresAt

    Peak.TextScenes[self.id] = self
    return self
end

function Scene:Destroy()
    self:StopRender()
    Peak.TextScenes[self.id] = nil
end

function Scene:StartRender()
    if self.isRendered then return end
    self.renderer = Peak.SceneRenderers.GetRenderer(false)
    if not self.renderer then return end

    self.isRendered = true
    Peak.SceneRenderers.Send(self.renderer, "setSceneData", self.displayData)
    Peak.SceneRenderers.Send(self.renderer, "setSceneId", self.id)
    self:RefreshVisibility()
    EnsureTextSceneRenderingThread()
end

function Scene:StopRender()
    if self.renderer then
        Peak.SceneRenderers.Send(self.renderer, "setVisible", false)
        Peak.SceneRenderers.ReleaseRenderer(self.renderer)
        self.renderer = nil
    end
    self.isRendered = false
end

function Scene:RefreshVisibility()
    if not self.renderer then return end

    local visibility = self.displayData.visibility or "always"
    if visibility == "interaction" and not self.revealed then
        Peak.SceneRenderers.Send(self.renderer, "setEye", true)
    elseif visibility == "interaction_visible" and not self.revealed then
        Peak.SceneRenderers.Send(self.renderer, "setEye", true)
    elseif visibility == "close" and not self.isClose then
        Peak.SceneRenderers.Send(self.renderer, "setEye", true)
    else
        Peak.SceneRenderers.Send(self.renderer, "setEye", false)
    end
    Peak.SceneRenderers.Send(self.renderer, "setVisible", true)
end

function Scene:RenderFrame(distance)
    if ScenesHidden or not self.renderer then return end

    local visibility = self.displayData.visibility or "always"

    if visibility == "close" then
        local closeDist = tonumber(self.displayData.closeDistance) or Config.SceneDefaultCloseDistance
        local nextClose = distance <= closeDist
        if nextClose ~= self.isClose then
            self.isClose = nextClose
            self:RefreshVisibility()
        end
    end

    if (visibility == "interaction_visible" and not self.revealed) or (visibility == "close" and not self.isClose) then
        if distance <= 2.0 and IsControlJustReleased(0, 38) then
            self.revealed = true
            self:RefreshVisibility()
        end
    end

    local txd, txn = Peak.SceneRenderers.Texture(self.renderer)
    if not txd or not txn then return end

    local rotation = Peak.SceneUtils.ResolveRenderRotation(self.coords, self.rotation)
    local scale = Config.SceneScale or 0.1
    local width = 25.0 * scale
    local height = ((Config.SceneRendererHeight or 720) / (Config.SceneRendererWidth or 1280)) * width

    DrawMarker(
        8,
        self.coords.x, self.coords.y, self.coords.z,
        0.0, 0.0, 0.0,
        rotation.x, rotation.y, rotation.z,
        width, height, 0.0,
        255, 255, 255, 255,
        false, false, 2, false,
        txd, txn, false
    )
end

function EnsureTextSceneRenderingThread()
    if renderingThreadActive then return end
    renderingThreadActive = true

    CreateThread(function()
        while renderingThreadActive do
            local pedCoords = GetEntityCoords(PlayerPedId())
            local activeCount = 0

            for _, scene in pairs(Peak.TextScenes) do
                local distance = #(pedCoords - sceneCoords(scene))
                local renderDistance = tonumber(scene.displayData.distance) or Config.SceneDefaultDistance

                if distance <= renderDistance then
                    activeCount = activeCount + 1
                    if not scene.isRendered then scene:StartRender() end
                    scene:RenderFrame(distance)
                elseif scene.isRendered then
                    scene:StopRender()
                end
            end

            if activeCount == 0 then
                Wait(500)
            else
                Wait(0)
            end
        end
    end)
end

RegisterNetEvent("peak-sprays:cl:addTextScene", function(data)
    if Peak.TextScenes[data.id] then
        Peak.TextScenes[data.id]:Destroy()
    end
    Peak.CreateTextScene(data)
    EnsureTextSceneRenderingThread()
end)

RegisterNetEvent("peak-sprays:cl:deleteTextScenes", function(ids)
    for _, id in ipairs(ids or {}) do
        if Peak.TextScenes[id] then
            Peak.TextScenes[id]:Destroy()
        end
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, scene in pairs(Peak.TextScenes) do
        scene:StopRender()
    end
    for rendererName in pairs(loadedDuis) do
        Peak.SceneRenderers.DestroyRenderer(rendererName)
    end
end)
