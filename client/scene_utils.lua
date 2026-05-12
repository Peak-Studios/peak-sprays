Peak = Peak or {}
Peak.SceneUtils = Peak.SceneUtils or {}

local hasGlm, glm = pcall(require, "glm")
if not hasGlm then glm = nil end

local function rotationToDirection(rotation)
    local rotX = math.rad(rotation.x)
    local rotZ = math.rad(rotation.z)
    local cosX = math.abs(math.cos(rotX))
    return vector3(-math.sin(rotZ) * cosX, math.cos(rotZ) * cosX, math.sin(rotX))
end

local function safeNormalize(vec)
    local length = #(vec)
    if length <= 0.001 then return vector3(0.0, 0.0, 1.0) end
    return vec / length
end

local function fallbackNormalToRotation(normal)
    normal = normal or vector3(0.0, 0.0, 1.0)
    if math.abs(normal.z) > 0.85 then
        local camRot = GetFinalRenderedCamRot(2)
        return vector3(0.0, 0.0, camRot.z)
    end

    local heading = GetHeadingFromVector_2d(normal.x, normal.y)
    return vector3(90.0, 0.0, heading)
end

function Peak.SceneUtils.GetCameraRay(distance)
    local camRot = GetGameplayCamRot(2)
    local camPos = GetGameplayCamCoord()
    local direction = rotationToDirection(camRot)
    local destination = camPos + direction * distance
    local handle = StartExpensiveSynchronousShapeTestLosProbe(
        camPos.x, camPos.y, camPos.z,
        destination.x, destination.y, destination.z,
        -1, PlayerPedId(), 7
    )
    local _, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(handle)
    if hit ~= 0 then
        return true, endCoords, entityHit, surfaceNormal
    end
    return false, destination, 0, vector3(0.0, 0.0, 1.0)
end

function Peak.SceneUtils.VecToTable(vec)
    if not vec then return nil end
    return { x = vec.x, y = vec.y, z = vec.z }
end

function Peak.SceneUtils.TableToVec(data)
    if not data then return nil end
    return vector3(data.x + 0.0, data.y + 0.0, data.z + 0.0)
end

function Peak.SceneUtils.NormalVectorToRot(normalVec)
    if not normalVec then return fallbackNormalToRotation() end

    if glm then
        local ok, rotation = pcall(function()
            local normal = glm.normalize(normalVec)
            local epsilon = 0.01
            local quatRot = quat(180, glm.forward())
            local finalQuat = nil

            if glm.approx(glm.abs(normal.z), 1, epsilon) then
                local camRot = GetFinalRenderedCamRot(2)
                local signZ = glm.sign(normal.z) * -camRot.z - 90.0
                finalQuat = glm.quatlookRotation(normal, glm.right()) * quat(signZ, glm.up())
            else
                if glm.approx(normal.y, 1, epsilon) then
                    finalQuat = glm.quatlookRotation(normal, -glm.up())
                    quatRot = quat(180, glm.right())
                else
                    finalQuat = glm.quatlookRotation(normal, glm.up())
                end
            end

            local euler = vec3(glm.extractEulerAngleYXZ(finalQuat * quatRot))
            return glm.deg(vec3(euler[2], euler[1], euler[3]))
        end)

        if ok and rotation then return rotation end
    end

    return fallbackNormalToRotation(normalVec)
end

function Peak.SceneUtils.FinalRotationToDirection(rotation)
    local rotX = math.rad(rotation.x)
    local rotY = math.rad(rotation.y)

    return vector3(
        math.sin(rotY) * math.abs(math.cos(rotX)),
        -math.sin(rotX),
        math.cos(rotY) * math.abs(math.cos(rotX))
    )
end

function Peak.SceneUtils.ComputeRotation(coords, normal, rotationType)
    rotationType = rotationType or "rotateGround"

    if rotationType == "rotateTorwards" then
        return nil
    end

    if rotationType == "rotateKeep" then
        local camPos = GetGameplayCamCoord()
        local direction = camPos - coords
        direction = safeNormalize(vector3(direction.x, direction.y, 0.0))
        return Peak.SceneUtils.NormalVectorToRot(direction)
    end

    return Peak.SceneUtils.NormalVectorToRot(normal or vector3(0.0, 0.0, 1.0))
end

function Peak.SceneUtils.ResolveRenderRotation(coords, storedRotation)
    if storedRotation then return storedRotation end

    local camPos = GetGameplayCamCoord()
    local direction = safeNormalize(camPos - coords)
    return Peak.SceneUtils.NormalVectorToRot(direction)
end

function Peak.SceneUtils.Clone(data)
    if type(data) ~= "table" then return data end
    local cloned = {}
    for key, value in pairs(data) do
        cloned[key] = Peak.SceneUtils.Clone(value)
    end
    return cloned
end
