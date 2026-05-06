--- ============================================================
--- CUSTOM CLIENT HOOKS
--- Use this file to add your own custom logic, overrides, and integrations.
--- ============================================================

Open = Open or {}

-- ============================================================
-- PERMISSIONS & VALIDATION
-- ============================================================

--- Called before a player can start spray painting.
--- Return true to allow, false to deny.
--- @return boolean
function CanSpray()
    -- Example:
    -- local job = Peak.Client.GetPlayerJob()
    -- if job.name == 'police' then return false end
    return true
end

--- Called before a player can start erasing.
--- Return true to allow, false to deny.
--- @return boolean
function CanErase()
    return true
end

-- ============================================================
-- EVENTS & CALLBACKS
-- ============================================================

--- Called after a painting is successfully saved/validated.
--- @param paintingId number The database ID of the saved painting
--- @param center vector3 The world center of the painting
function OnSprayCompleted(paintingId, center)
    SprayUtils.DebugPrint('[Custom] Spray completed - Painting ID:', paintingId)
    -- TriggerEvent('your_script:onSprayCreated', paintingId, center)
end

--- Called after an erase operation is saved/validated.
--- @param paintingId number The database ID of the erased painting
function OnSprayRemoved(paintingId)
    SprayUtils.DebugPrint('[Custom] Spray removed - Painting ID:', paintingId)
    -- TriggerEvent('your_script:onSprayRemoved', paintingId)
end

-- ============================================================
-- CUSTOM SUBSYSTEM OVERRIDES
-- ============================================================

--- Use these to override default framework logic for notifications, etc.
--- Return true/result to stop default logic, nil to continue.

--- @param msg string
--- @param type string 'success'|'error'|'info'|'warning'
--- @param duration number milliseconds
--- @return boolean|nil
function Open.CustomNotify(msg, type, duration)
    return nil
end

--- @param label string
--- @param duration number
--- @param options table
--- @return boolean|nil
function Open.CustomProgressBar(label, duration, options)
    return nil
end

--- @param targetType string 'coords'|'entity'
--- @param id string|nil
--- @param coordsOrEntity vector3|number
--- @param options table
--- @param distance number
--- @return any|nil
function Open.CustomTarget(targetType, id, coordsOrEntity, options, distance)
    return nil
end

--- @param playerId? number server id (nil = local player)
--- @return boolean|nil return true/false to override, nil to use detected system
function Open.CustomIsPlayerDead(playerId)
    return nil
end

-- ============================================================
-- VEHICLE HOOKS
-- ============================================================

--- @param vehicle number
--- @param seat number
function Open.OnEnterVehicle(vehicle, seat)
end

--- @param vehicle number
function Open.OnExitVehicle(vehicle)
end

-- ============================================================
-- EXPORTS
-- ============================================================

--- Returns all known paintings on the client.
--- @return table<number, table>
exports('GetAllSprays', function()
    return KnownPaintings or {}
end)

--- Returns a specific painting by ID.
--- @param paintingId number
--- @return table|nil
exports('GetSprayById', function(paintingId)
    if not KnownPaintings then return nil end
    return KnownPaintings[paintingId]
end)

--- Returns the current spray state.
--- @return string
exports('GetSprayState', function()
    return SprayState and SprayState.mode or 'idle'
end)

--- Returns nearby paintings within a radius.
--- @param coords vector3
--- @param radius number
--- @return table
exports('GetNearbyPaintings', function(coords, radius)
    local result = {}
    if not KnownPaintings or not coords then return result end
    radius = radius or 50.0
    for id, painting in pairs(KnownPaintings) do
        if painting.center and #(coords - painting.center) <= radius then
            table.insert(result, painting)
        end
    end
    return result
end)
