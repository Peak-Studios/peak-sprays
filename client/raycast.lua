RaycastModule = {}

local function RotationToDirection(rotation)
    local x = math.rad(rotation.x)
    local z = math.rad(rotation.z)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function GetSafeShapeTestResult(handle)
    if type(handle) ~= "number" or handle <= 0 then return 0, 0, vector3(0,0,0), vector3(0,0,0), 0 end
    
    local status, hit, endCoords, surfaceNormal, entity = GetShapeTestResult(handle)
    return status, hit, endCoords, surfaceNormal, entity
end

local function GetSafeShapeTestResultIncludingMaterial(handle)
    if type(handle) ~= "number" or handle <= 0 then return 0, 0, vector3(0,0,0), vector3(0,0,0), 0, 0 end
    
    local status, hit, endCoords, surfaceNormal, materialHash, entity = GetShapeTestResultIncludingMaterial(handle)
    return status, hit, endCoords, surfaceNormal, materialHash, entity
end

function RaycastModule.FromCamera(distance)
    local cameraRotation = GetGameplayCamRot(2)
    local cameraCoord = GetGameplayCamCoord()
    local direction = RotationToDirection(cameraRotation)
    local destination = cameraCoord + direction * distance
    
    if #(destination - cameraCoord) < 0.001 then
        return false, vector3(0,0,0), vector3(0,0,0), 0
    end
    
    local handle = StartExpensiveSynchronousShapeTestLosProbe(cameraCoord.x, cameraCoord.y, cameraCoord.z, destination.x, destination.y, destination.z, -1, PlayerPedId(), 7)
    local status, hit, endCoords, surfaceNormal, entity = GetSafeShapeTestResult(handle)
    
    if status == 0 then return false, vector3(0,0,0), vector3(0,0,0), 0 end
    return hit ~= 0, endCoords, surfaceNormal, entity
end

function RaycastModule.FromCameraWithMaterial(distance)
    local cameraRotation = GetGameplayCamRot(2)
    local cameraCoord = GetGameplayCamCoord()
    local direction = RotationToDirection(cameraRotation)
    local destination = cameraCoord + direction * distance
    
    if #(destination - cameraCoord) < 0.001 then
        return false, vector3(0,0,0), vector3(0,0,0), 0, 0
    end
    
    local handle = StartExpensiveSynchronousShapeTestLosProbe(cameraCoord.x, cameraCoord.y, cameraCoord.z, destination.x, destination.y, destination.z, -1, PlayerPedId(), 7)
    local status, hit, endCoords, surfaceNormal, materialHash, entity = GetSafeShapeTestResultIncludingMaterial(handle)
    
    if status == 0 then return false, vector3(0,0,0), vector3(0,0,0), 0, 0 end
    return hit ~= 0, endCoords, surfaceNormal, materialHash, entity
end

function RaycastModule.FromPoint(point, direction, distance)
    local destination = point + direction * distance
    
    if #(destination - point) < 0.001 then
        return false, vector3(0,0,0), vector3(0,0,0)
    end
    
    local handle = StartExpensiveSynchronousShapeTestLosProbe(point.x, point.y, point.z, destination.x, destination.y, destination.z, 1, PlayerPedId(), 7)
    local status, hit, endCoords, surfaceNormal, entity = GetSafeShapeTestResult(handle)
    
    if status == 0 then return false, vector3(0,0,0), vector3(0,0,0) end
    return hit ~= 0, endCoords, surfaceNormal
end

function RaycastModule.RayPlaneIntersection(rayOrigin, rayDir, planePoint, planeNormal)
    local d = dot(rayDir, planeNormal)
    if math.abs(d) < 1e-6 then return false, vector3(0,0,0) end
    local t = dot(planePoint - rayOrigin, planeNormal) / d
    if t < 0.0 then return false, vector3(0,0,0) end
    return true, rayOrigin + rayDir * t
end

function RaycastModule.FromCameraToPlane(planePoint, planeNormal, maxDistance)
    local cameraRotation = GetGameplayCamRot(2)
    local cameraCoord = GetGameplayCamCoord()
    local direction = RotationToDirection(cameraRotation)
    
    local hit, hitCoords = RaycastModule.RayPlaneIntersection(cameraCoord, direction, planePoint, planeNormal)
    if hit then
        if #(hitCoords - cameraCoord) <= maxDistance then
            return true, hitCoords, cameraCoord, direction
        end
    end
    return false, vector3(0,0,0), cameraCoord, direction
end

function RaycastModule.ComputeRectangle(p1, p2, normal)
    local normNormal = norm(normal)
    local up = vector3(0.0, 0.0, 1.0)
    local right = norm(cross(normNormal, up))
    
    if #right < 0.001 then
        local forward = vector3(0.0, 1.0, 0.0)
        right = norm(cross(normNormal, forward))
    end
    
    local upAxis = norm(cross(right, normNormal))
    local relative = p2 - p1
    
    local dRight = dot(relative, right)
    local dUp = dot(relative, upAxis)
    
    local minRight = math.min(0.0, dRight)
    local maxRight = math.max(0.0, dRight)
    local minUp = math.min(0.0, dUp)
    local maxUp = math.max(0.0, dUp)
    
    local width = maxRight - minRight
    local height = maxUp - minUp
    
    if width > Config.MaxPaintAreaWidth then
        local diff = width - Config.MaxPaintAreaWidth
        minRight = minRight + diff * 0.5
        maxRight = maxRight - diff * 0.5
    end
    
    if height > Config.MaxPaintAreaHeight then
        local diff = height - Config.MaxPaintAreaHeight
        minUp = minUp + diff * 0.5
        maxUp = maxUp - diff * 0.5
    end
    
    local offset = normNormal * Config.WallOffset
    local bl = p1 + right * minRight + upAxis * minUp + offset
    local br = p1 + right * maxRight + upAxis * minUp + offset
    local tl = p1 + right * minRight + upAxis * maxUp + offset
    local tr = p1 + right * maxRight + upAxis * maxUp + offset
    
    return {
        topLeft = tl,
        topRight = tr,
        bottomLeft = bl,
        bottomRight = br
    }, right, upAxis
end

function RaycastModule.IsSurfaceAllowed(material)
    if not Config.AllowedSurfaceMaterials or #Config.AllowedSurfaceMaterials == 0 then
        return true
    end
    for _, allowed in ipairs(Config.AllowedSurfaceMaterials) do
        if allowed == material then return true end
    end
    return false
end

function RaycastModule.ValidateCorners(corners, normal, threshold)
    threshold = threshold or 0.5
    local checkDir = -normal
    local points = { corners.topLeft, corners.topRight, corners.bottomLeft, corners.bottomRight }
    
    for _, p in ipairs(points) do
        local start = p + normal * 0.5
        local hit, hitCoords, _ = RaycastModule.FromPoint(start, checkDir, 1.5)
        if not hit then return false, "surface_overflow" end
        if #(hitCoords - p) > threshold then return false, "surface_overflow" end
    end
    return true
end

function RaycastModule.WorldToCanvas(coords, corners, right, up)
    local bl = corners.bottomLeft
    local br = corners.bottomRight
    local tl = corners.topLeft
    
    local horizontal = br - bl
    local vertical = tl - bl
    
    local dotHoriz = dot(horizontal, horizontal)
    local dotVert = dot(vertical, vertical)
    
    if dotHoriz < 1e-6 or dotVert < 1e-6 then
        return false, 0, 0
    end
    
    local relative = coords - bl
    local u = dot(relative, horizontal) / dotHoriz
    local v = dot(relative, vertical) / dotVert
    
    local withinBounds = (u >= -0.05)
    u = SprayUtils.Clamp(u, 0.0, 1.0)
    v = SprayUtils.Clamp(v, 0.0, 1.0)
    
    return withinBounds, u, v
end

function RaycastModule.DrawRectOutline(corners, r, g, b, a)
    DrawLine(corners.topLeft.x, corners.topLeft.y, corners.topLeft.z, corners.topRight.x, corners.topRight.y, corners.topRight.z, r, g, b, a)
    DrawLine(corners.topRight.x, corners.topRight.y, corners.topRight.z, corners.bottomRight.x, corners.bottomRight.y, corners.bottomRight.z, r, g, b, a)
    DrawLine(corners.bottomRight.x, corners.bottomRight.y, corners.bottomRight.z, corners.bottomLeft.x, corners.bottomLeft.y, corners.bottomLeft.z, r, g, b, a)
    DrawLine(corners.bottomLeft.x, corners.bottomLeft.y, corners.bottomLeft.z, corners.topLeft.x, corners.topLeft.y, corners.topLeft.z, r, g, b, a)
end

function RaycastModule.DrawCrosshair(coords, r, g, b)
    local size = 0.02
    DrawLine(coords.x - size, coords.y, coords.z, coords.x + size, coords.y, coords.z, r, g, b, 255)
    DrawLine(coords.x, coords.y - size, coords.z, coords.x, coords.y + size, coords.z, r, g, b, 255)
    DrawLine(coords.x, coords.y, coords.z - size, coords.x, coords.y, coords.z + size, r, g, b, 255)
end

function norm(v)
    local length = #v
    if length < 1e-4 then return vector3(0, 0, 0) end
    return v / length
end

function cross(a, b)
    return vector3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
end

function dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

_G.RaycastModule = RaycastModule
