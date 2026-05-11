--- ============================================================
--- CUSTOM SERVER HOOKS
--- Use this file to add your own custom logic, overrides, and integrations.
--- ============================================================

Open = Open or {}

-- ============================================================
-- PERMISSIONS & VALIDATION
-- ============================================================

--- Called before a player can save a spray painting.
--- @param source number Player server ID
--- @return boolean
function ServerCanSpray(source)
    -- Example:
    -- if not Peak.Server.IsAdmin(source) then return false end
    return true
end

--- Called before a player can erase a painting.
--- @param source number
--- @return boolean
function ServerCanErase(source)
    return true
end

--- Called before a player can save a text scene/sign.
--- @param source number
--- @param payload table
--- @return boolean
function ServerCanCreateScene(source, payload)
    return true
end

--- Called before a non-owner, non-admin can delete a text scene/sign.
--- Owners and admins are allowed before this hook is checked.
--- @param source number
--- @param scene table
--- @return boolean
function ServerCanDeleteScene(source, scene)
    return false
end

-- ============================================================
-- EVENTS & CALLBACKS
-- ============================================================

--- Called after a painting is saved to the database.
--- @param source number
--- @param paintingId number
--- @param data table Raw painting data
function OnServerSprayCompleted(source, paintingId, data)
    SprayUtils.DebugPrint('[Custom] Spray saved - ID:', paintingId, 'by source:', source)
end

--- Called after a painting is removed from the database.
--- @param source number
--- @param paintingId number
function OnServerSprayRemoved(source, paintingId)
    SprayUtils.DebugPrint('[Custom] Spray removed - ID:', paintingId, 'by source:', source)
end

--- @param source number
--- @param sceneId number
--- @param scene table
function OnServerTextSceneCreated(source, sceneId, scene)
    SprayUtils.DebugPrint('[Custom] Text scene saved - ID:', sceneId, 'by source:', source)
end

--- @param source number
--- @param sceneId number
--- @param scene table
function OnServerTextSceneDeleted(source, sceneId, scene)
    SprayUtils.DebugPrint('[Custom] Text scene deleted - ID:', sceneId, 'by source:', source)
end

-- ============================================================
-- PLAYER HOOKS
-- ============================================================

--- @param source number
--- @param playerData table
function Open.OnPlayerLoaded(source, playerData)
end

--- @param source number
function Open.OnPlayerUnloaded(source)
end

-- ============================================================
-- CUSTOM MONEY OVERRIDES
-- ============================================================

--- Return true/result to override, nil to use default framework logic.

--- @param source number
--- @param amount number
--- @param moneyType string
--- @return boolean|nil
function Open.AddMoney(source, amount, moneyType)
    return nil
end

--- @param source number
--- @param amount number
--- @param moneyType string
--- @return boolean|nil
function Open.RemoveMoney(source, amount, moneyType)
    return nil
end

--- @param source number
--- @param moneyType string
--- @return number|nil
function Open.GetMoney(source, moneyType)
    return nil
end

-- ============================================================
-- MISC
--- @param source number
--- @return boolean|nil
function Open.CustomIsPlayerDead(source)
    return nil
end
