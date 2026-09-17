Peak = Peak or {}
Peak.Placement = Peak.Placement or {}

local PlacementStatus = {
    IDLE = "idle",
    STUDIO = "studio",
    PLACING = "placing",
    PAINTING = "painting",
    PUBLISHING = "publishing"
}

local PlacementState = {
    status = PlacementStatus.IDLE,
    sessionToken = nil,
    composition = nil,
    presetSize = "medium",
    rotation = 0.0,
    snapRotation = true,
    duplicateMode = false,
    center = nil,
    normal = nil,
    corners = nil,
    width = 1.6,
    height = 1.6,
    aspectRatio = 1.0,
    rightAxis = nil,
    upAxis = nil,
    pendingRequest = false,
    placedCount = 0
}

local FitCache = {
    lastTime = 0,
    center = nil,
    normal = nil,
    fitW = 1.6,
    fitH = 1.6
}

local SIZES = {
    small = 0.8,
    medium = 1.6,
    large = 2.5,
    mural = 4.0
}

--- Probes the surface boundaries in 4 directions to determine the maximum unclipped rectangle
function RaycastModule.FitToWall(center, normal, maxDist)
    maxDist = maxDist or 5.0
    local normNormal = norm(normal)
    local worldUp = vector3(0.0, 0.0, 1.0)
    local right = norm(cross(normNormal, worldUp))
    if #right < 0.001 then
        right = norm(cross(normNormal, vector3(0.0, 1.0, 0.0)))
    end
    local up = norm(cross(right, normNormal))

    local probeStep = 0.2
    local leftDist = 0.0
    local rightDist = 0.0
    local upDist = 0.0
    local downDist = 0.0

    -- Probe +Right
    for dist = probeStep, maxDist * 0.5, probeStep do
        local p = center + (right * dist) + (normNormal * 0.05)
        local hit, hitCoord = RaycastModule.FromPoint(p, -normNormal, 0.5)
        if not hit or #(hitCoord - (p - normNormal * 0.05)) > 0.35 then break end
        rightDist = dist
    end

    -- Probe -Right
    for dist = probeStep, maxDist * 0.5, probeStep do
        local p = center - (right * dist) + (normNormal * 0.05)
        local hit, hitCoord = RaycastModule.FromPoint(p, -normNormal, 0.5)
        if not hit or #(hitCoord - (p - normNormal * 0.05)) > 0.35 then break end
        leftDist = dist
    end

    -- Probe +Up
    for dist = probeStep, maxDist * 0.5, probeStep do
        local p = center + (up * dist) + (normNormal * 0.05)
        local hit, hitCoord = RaycastModule.FromPoint(p, -normNormal, 0.5)
        if not hit or #(hitCoord - (p - normNormal * 0.05)) > 0.35 then break end
        upDist = dist
    end

    -- Probe -Up (Down)
    for dist = probeStep, maxDist * 0.5, probeStep do
        local p = center - (up * dist) + (normNormal * 0.05)
        local hit, hitCoord = RaycastModule.FromPoint(p, -normNormal, 0.5)
        if not hit or #(hitCoord - (p - normNormal * 0.05)) > 0.35 then break end
        downDist = dist
    end

    local fitWidth = math.max(0.6, math.min(leftDist, rightDist) * 2.0)
    local fitHeight = math.max(0.6, math.min(upDist, downDist) * 2.0)
    return fitWidth, fitHeight, right, up
end

--- Calculates placement dimensions preserving original composition aspect ratio
local function CalculatePlacementDimensions(hitCoords, normal, presetSize, aspectRatio)
    if presetSize == "fit" then
        local now = GetGameTimer()
        local needsProbe = not FitCache.center
            or (now - FitCache.lastTime > 300)
            or (#(hitCoords - FitCache.center) > 0.15)
            or (FitCache.normal and math.abs(dot(norm(normal), norm(FitCache.normal)) - 1.0) > 0.05)

        if needsProbe then
            local maxW, maxH = RaycastModule.FitToWall(hitCoords, normal, Config.MaxPaintAreaWidth or 5.0)
            FitCache.lastTime = now
            FitCache.center = hitCoords
            FitCache.normal = normal

            -- Fit within maxW and maxH preserving aspect ratio
            if (maxW / maxH) > aspectRatio then
                FitCache.fitW = maxH * aspectRatio
                FitCache.fitH = maxH
            else
                FitCache.fitW = maxW
                FitCache.fitH = maxW / aspectRatio
            end
        end
        return FitCache.fitW, FitCache.fitH
    end

    local baseW = SIZES[presetSize] or SIZES.medium
    local baseH = baseW / aspectRatio
    return baseW, baseH
end

--- Computes a 3D rotated rectangle on a surface plane centered at `center`
function RaycastModule.ComputeRotatedCorners(center, normal, width, height, angleDeg)
    local normNormal = norm(normal)
    local worldUp = vector3(0.0, 0.0, 1.0)
    local baseRight = norm(cross(normNormal, worldUp))
    if #baseRight < 0.001 then
        baseRight = norm(cross(normNormal, vector3(0.0, 1.0, 0.0)))
    end
    local baseUp = norm(cross(baseRight, normNormal))

    -- Rotate right and up axes by angleDeg around normal
    local rad = math.rad(angleDeg or 0.0)
    local cosA = math.cos(rad)
    local sinA = math.sin(rad)

    local rotRight = norm(baseRight * cosA + baseUp * sinA)
    local rotUp = norm(cross(rotRight, normNormal))

    local halfW = width * 0.5
    local halfH = height * 0.5
    local offset = normNormal * (Config.WallOffset or 0.01)

    local tl = center - (rotRight * halfW) + (rotUp * halfH) + offset
    local tr = center + (rotRight * halfW) + (rotUp * halfH) + offset
    local bl = center - (rotRight * halfW) - (rotUp * halfH) + offset
    local br = center + (rotRight * halfW) - (rotUp * halfH) + offset

    return {
        topLeft = tl,
        topRight = tr,
        bottomLeft = bl,
        bottomRight = br
    }, rotRight, rotUp
end

--- Draws alignment guides: level horizon line, plumb line, and center crosshair
function RaycastModule.DrawAlignmentGuides(center, normal, right, up, width, height)
    -- Center crosshair
    local crossLen = 0.15
    DrawLine(center.x - right.x * crossLen, center.y - right.y * crossLen, center.z - right.z * crossLen,
             center.x + right.x * crossLen, center.y + right.y * crossLen, center.z + right.z * crossLen,
             214, 255, 98, 240)
    DrawLine(center.x - up.x * crossLen, center.y - up.y * crossLen, center.z - up.z * crossLen,
             center.x + up.x * crossLen, center.y + up.y * crossLen, center.z + up.z * crossLen,
             214, 255, 98, 240)

    -- Horizon level indicator (world level line)
    local normNormal = norm(normal)
    local levelRight = norm(cross(normNormal, vector3(0.0, 0.0, 1.0)))
    if #levelRight > 0.001 then
        local guideLen = (width * 0.5) + 0.25
        DrawLine(center.x - levelRight.x * guideLen, center.y - levelRight.y * guideLen, center.z - levelRight.z * guideLen,
                 center.x + levelRight.x * guideLen, center.y + levelRight.y * guideLen, center.z + levelRight.z * guideLen,
                 255, 255, 255, 100)
    end
end

--- Initiates Smart Placement for a graffiti composition
function StartSmartPlacement(composition, presetSize, duplicateMode)
    if PlacementState.status == PlacementStatus.PAINTING or PlacementState.status == PlacementStatus.PUBLISHING then
        return
    end

    local token = tostring(GetGameTimer()) .. "_" .. tostring(math.random(1000, 9999))
    PlacementState.status = PlacementStatus.PLACING
    PlacementState.sessionToken = token
    PlacementState.composition = composition
    PlacementState.presetSize = presetSize or "medium"
    PlacementState.rotation = 0.0
    PlacementState.duplicateMode = duplicateMode == true
    PlacementState.pendingRequest = false
    PlacementState.placedCount = 0
    SprayState.mode = "placing"

    local compW = (composition and composition.width) or 1024
    local compH = (composition and composition.height) or 1024
    PlacementState.aspectRatio = math.max(0.1, math.min(10.0, compW / compH))

    FitCache.lastTime = 0
    FitCache.center = nil
    FitCache.normal = nil

    SetFollowPedCamViewMode(4)
    Peak.Client.ShowTextUI(
        "[LMB] Place/Paint  |  [Scroll] Rotate  |  [R] Snap 45°  |  [1-4] Size  |  [E] Fit Wall  |  [RMB/Esc] Cancel",
        "bottom-center"
    )

    CreateThread(function()
        while PlacementState.status == PlacementStatus.PLACING or
              PlacementState.status == PlacementStatus.PAINTING or
              PlacementState.status == PlacementStatus.PUBLISHING do
            Wait(0)
            local ped = PlayerPedId()

            -- Disable firing and conflicting controls
            for _, control in ipairs({0, 24, 25, 47, 58, 140, 141, 142, 257, 263, 264}) do
                DisableControlAction(0, control, true)
            end
            DisablePlayerFiring(ped, true)

            -- If currently painting or publishing, freeze input interaction
            if PlacementState.status == PlacementStatus.PLACING and not PlacementState.pendingRequest then
                local hit, hitCoords, normal, _ = RaycastModule.FromCamera(Config.SelectionMaxDistance or 10.0)
                if hit and normal then
                    PlacementState.center = hitCoords
                    PlacementState.normal = normal

                    -- Determine width & height with aspect-ratio preservation and debounced caching
                    local w, h = CalculatePlacementDimensions(
                        hitCoords,
                        normal,
                        PlacementState.presetSize,
                        PlacementState.aspectRatio
                    )

                    PlacementState.width = w
                    PlacementState.height = h

                    -- Compute rotated corners on wall
                    local corners, right, up = RaycastModule.ComputeRotatedCorners(
                        hitCoords,
                        normal,
                        w,
                        h,
                        PlacementState.rotation
                    )
                    PlacementState.corners = corners
                    PlacementState.rightAxis = right
                    PlacementState.upAxis = up

                    -- Validate surface
                    local ok, _ = RaycastModule.ValidateCorners(corners, normal, 0.4)
                    local rCol = ok and 214 or 239
                    local gCol = ok and 255 or 68
                    local bCol = ok and 98 or 68

                    -- Draw visual rectangle outline & alignment guides
                    RaycastModule.DrawRectOutline(corners, rCol, gCol, bCol, 220)
                    RaycastModule.DrawAlignmentGuides(hitCoords, normal, right, up, w, h)

                    -- Inputs: Rotation via scroll wheel
                    if IsControlJustPressed(0, 241) then -- Scroll Up
                        PlacementState.rotation = (PlacementState.rotation + (PlacementState.snapRotation and 15 or 5)) % 360
                    elseif IsControlJustPressed(0, 242) then -- Scroll Down
                        PlacementState.rotation = (PlacementState.rotation - (PlacementState.snapRotation and 15 or 5)) % 360
                    end

                    -- Input: Snap 45° toggle
                    if IsDisabledControlJustPressed(0, 45) then -- Key R
                        PlacementState.rotation = math.floor((PlacementState.rotation + 22.5) / 45.0) * 45.0
                        PlacementState.rotation = (PlacementState.rotation + 45.0) % 360
                        Peak.Client.Notify(("Snapped rotation: %d°"):format(math.floor(PlacementState.rotation)), "info", 1500)
                    end

                    -- Input: Sizing Presets (Keys 1-4: 157, 158, 159, 160)
                    if IsDisabledControlJustPressed(0, 157) then -- 1: Small
                        PlacementState.presetSize = "small"
                    elseif IsDisabledControlJustPressed(0, 158) then -- 2: Medium
                        PlacementState.presetSize = "medium"
                    elseif IsDisabledControlJustPressed(0, 159) then -- 3: Large
                        PlacementState.presetSize = "large"
                    elseif IsDisabledControlJustPressed(0, 160) then -- 4: Mural
                        PlacementState.presetSize = "mural"
                    elseif IsDisabledControlJustPressed(0, 38) then -- E: Fit to Wall toggle
                        PlacementState.presetSize = (PlacementState.presetSize == "fit") and "medium" or "fit"
                        Peak.Client.Notify(PlacementState.presetSize == "fit" and "Fit to Wall Mode: Active" or "Standard Sizing", "info", 1500)
                    end

                    -- Input: Confirm Placement (LMB or Enter)
                    if IsDisabledControlJustPressed(0, 24) or IsDisabledControlJustPressed(0, 191) then
                        if not ok then
                            Peak.Client.Notify("Cannot place here: surface angle or edge overflow", "error", 3000)
                        else
                            ConfirmPlacement(token)
                        end
                    end
                end
            end

            -- Input: Cancel Placement (RMB or Backspace/Delete)
            -- Reachable during both PLACING and PAINTING states
            if IsDisabledControlJustPressed(0, 25) or IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 178) then
                CancelPlacement()
                return
            end
        end
    end)
end

function ConfirmPlacement(sessionToken)
    if PlacementState.status ~= PlacementStatus.PLACING or PlacementState.pendingRequest then
        return
    end
    if PlacementState.sessionToken ~= sessionToken then
        return
    end
    if not PlacementState.corners or not PlacementState.normal then
        return
    end

    local comp = PlacementState.composition or {}
    local center = PlacementState.center
    local corners = PlacementState.corners
    local normal = PlacementState.normal

    PlacementState.status = PlacementStatus.PAINTING
    PlacementState.pendingRequest = true

    -- Play spray sound and animation
    AttachSprayCanProp()
    Peak.Client.LoadAnimDict(Config.SprayAnimation.dict)
    TaskPlayAnim(PlayerPedId(), Config.SprayAnimation.dict, Config.SprayAnimation.anim, 8.0, -8.0, 3000, Config.SprayAnimation.flag, 0, false, false, false)
    StartSpraySound()
    StartSprayParticle(Config.DefaultColor)

    local strokeDoc = SprayUtils.NormalizePaintingDocument({
        isComposition = true,
        composition = comp,
        layers = comp.layers or {}
    })

    local requestId = ("req_%d_%d"):format(GetGameTimer(), math.random(100000, 999999))

    local payload = {
        requestId = requestId,
        corners = SprayUtils.CornersToTable(corners),
        normal = SprayUtils.Vec3ToTable(normal),
        strokeData = strokeDoc,
        canvasWidth = comp.width or Config.CanvasWidth or 1024,
        canvasHeight = comp.height or Config.CanvasHeight or 1024,
        worldX = center.x,
        worldY = center.y,
        worldZ = center.z,
        strokeCount = SprayUtils.CalculatePaintingStrokeCount(strokeDoc),
        activeItem = Config.SprayPaintItem
    }

    SetTimeout(1500, function()
        StopSprayParticle()
        StopSpraySound()
        DetachProp()
        ClearPedTasks(PlayerPedId())

        if PlacementState.sessionToken ~= sessionToken then
            return -- Discard stale session
        end

        PlacementState.status = PlacementStatus.PUBLISHING

        local result = Peak.Client.TriggerCallback("peak-sprays:savePainting", payload)

        if PlacementState.sessionToken ~= sessionToken then
            return -- Discard response if session changed in flight
        end

        PlacementState.pendingRequest = false

        if result and result.success then
            PlacementState.placedCount = PlacementState.placedCount + 1
            Peak.Client.Notify("Graffiti spray published!", "success", 4000)
            if OnSprayCompleted then OnSprayCompleted(result.id, center) end

            if PlacementState.duplicateMode then
                PlacementState.status = PlacementStatus.PLACING
                Peak.Client.Notify("Aim at next location to duplicate...", "info", 2500)
            else
                PlacementState.status = PlacementStatus.IDLE
                PlacementState.sessionToken = nil
                SprayState.mode = "idle"
                SetFollowPedCamViewMode(0)
                Peak.Client.HideTextUI()
            end
        else
            PlacementState.status = PlacementStatus.PLACING
            Peak.Client.Notify(result and result.message or "Failed to place spray", "error", 4000)
        end
    end)
end

function CancelPlacement()
    if PlacementState.status == PlacementStatus.PUBLISHING and PlacementState.pendingRequest then
        Peak.Client.Notify("Publishing in progress, please wait...", "warning", 2000)
        return
    end

    local wasDuplicate = PlacementState.duplicateMode
    local placedCount = PlacementState.placedCount

    PlacementState.sessionToken = nil
    PlacementState.pendingRequest = false
    SprayState.mode = "idle"

    StopSprayParticle()
    StopSpraySound()
    DetachProp()
    ClearPedTasks(PlayerPedId())
    SetFollowPedCamViewMode(0)
    Peak.Client.HideTextUI()

    -- If player was in duplicate mode and already placed sprays, exit cleanly to idle gameplay
    if wasDuplicate and placedCount > 0 then
        PlacementState.status = PlacementStatus.IDLE
        Peak.Client.Notify(("Duplicate placement finished (%d placed)"):format(placedCount), "info", 3000)
        return
    end

    PlacementState.status = PlacementStatus.STUDIO
    Peak.Client.Notify("Placement cancelled", "info", 2000)

    -- Re-open studio so player doesn't lose their work
    SendNUIMessage({
        action = "openStudio",
        composition = PlacementState.composition,
        step = "placement"
    })
    SetNuiFocus(true, true)
end
