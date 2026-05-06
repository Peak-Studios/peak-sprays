Peak = Peak or {}
Peak.Utils = {}
SprayUtils = SprayUtils or {}

-- ============================================================
-- GENERAL UTILS (PEAK)
-- ============================================================

--- Prints a debug message to the console if Config.Debug is enabled.
--- @param ... any Arguments to print
function Peak.Utils.Debug(...)
    if not Config.Debug then return end
    
    local args = {...}
    local strArgs = {}
    for i = 1, #args do
        strArgs[#strArgs + 1] = tostring(args[i])
    end
    
    print("^3[Peak:Debug]^0 " .. table.concat(strArgs, " "))
end

--- Prints a standard message to the console.
--- @param ... any Arguments to print
function Peak.Utils.print(...)
    local args = {...}
    local strArgs = {}
    for i = 1, #args do
        strArgs[#strArgs + 1] = tostring(args[i])
    end
    
    print("^2[Peak]^0 " .. table.concat(strArgs, " "))
end

--- Prints a warning message to the console.
--- @param ... any Arguments to print
function Peak.Utils.Warn(...)
    local args = {...}
    local strArgs = {}
    for i = 1, #args do
        strArgs[#strArgs + 1] = tostring(args[i])
    end
    
    print("^1[Peak:WARN]^0 " .. table.concat(strArgs, " "))
end

--- Performs a deep copy of a table.
--- @param obj any Object to copy
--- @return any Copied object
function Peak.Utils.DeepCopy(obj)
    if type(obj) ~= "table" then return obj end
    
    local res = {}
    for k, v in next, obj do
        res[Peak.Utils.DeepCopy(k)] = Peak.Utils.DeepCopy(v)
    end
    
    return setmetatable(res, Peak.Utils.DeepCopy(getmetatable(obj)))
end

--- Returns the number of elements in a table.
--- @param t table
--- @return number
function Peak.Utils.TableSize(t)
    local count = 0
    if t then
        for _ in pairs(t) do
            count = count + 1
        end
    end
    return count
end

--- Checks if a table contains a specific value.
--- @param t table
--- @param val any
--- @return boolean
function Peak.Utils.TableContains(t, val)
    if not t then return false end
    for _, v in pairs(t) do
        if v == val then
            return true
        end
    end
    return false
end

--- Merges two tables recursively.
--- @param t1 table Target table
--- @param t2 table Source table
--- @return table Merged table
function Peak.Utils.TableMerge(t1, t2)
    for k, v in pairs(t2) do
        if type(v) == "table" and type(t1[k]) == "table" then
            Peak.Utils.TableMerge(t1[k], v)
        else
            t1[k] = v
        end
    end
    return t1
end

--- Clamps a value between a minimum and maximum.
--- @param val number
--- @param min number
--- @param max number
--- @return number
function Peak.Utils.Clamp(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
end

--- Rounds a number to a specific number of decimal places.
--- @param val number
--- @param decimal number
--- @return number
function Peak.Utils.Round(val, decimal)
    local exp = 10 ^ (decimal or 0)
    return math.floor(val * exp + 0.5) / exp
end

--- Formats a number with commas.
--- @param val number
--- @return string
function Peak.Utils.FormatNumber(val)
    local str = tostring(math.floor(val))
    while true do
        local newStr, count = string.gsub(str, "^(-?%d+)(%d%d%d)", "%1,%2")
        str = newStr
        if count == 0 then break end
    end
    return str
end

--- Formats a number as a currency string.
--- @param val number
--- @return string
function Peak.Utils.FormatMoney(val)
    return "$" .. Peak.Utils.FormatNumber(val)
end

--- Generates a random string of a specific length.
--- @param length number
--- @return string
function Peak.Utils.RandomString(length)
    local charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local res = {}
    for i = 1, length do
        local rand = math.random(1, #charset)
        res[i] = charset:sub(rand, rand)
    end
    return table.concat(res)
end

--- Safely encodes data into JSON.
--- @param data any
--- @return string
function Peak.Utils.JsonEncode(data)
    local ok, res = pcall(json.encode, data)
    if ok then return res end
    Peak.Utils.Warn("JSON encode failed:", res)
    return "{}"
end

--- Safely decodes data from JSON.
--- @param data string
--- @return any|nil
function Peak.Utils.JsonDecode(data)
    if not data or data == "" then return nil end
    local ok, res = pcall(json.decode, data)
    if ok then return res end
    Peak.Utils.Warn("JSON decode failed:", res)
    return nil
end

--- Returns the current OS timestamp.
--- @return number
function Peak.Utils.GetTimestamp()
    return os.time()
end

--- Formats a timestamp into a readable string.
--- @param ts number
--- @param format string
--- @return string
function Peak.Utils.FormatTimestamp(ts, format)
    return os.date(format or "%Y-%m-%d %H:%M:%S", ts)
end

-- ============================================================
-- SPRAY-SPECIFIC UTILS (SPRAYUTILS)
-- ============================================================

--- Prints a spray-specific debug message.
--- @param ... any
function SprayUtils.DebugPrint(...)
    if Config.Debug then
        print("^3[Peak-Sprays][DEBUG]^0", ...)
    end
end

--- Converts a vector3 to a table.
--- @param v vector3
--- @return table {x, y, z}
function SprayUtils.Vec3ToTable(v)
    return { x = v.x, y = v.y, z = v.z }
end

--- Converts a table to a vector3.
--- @param t table {x, y, z}
--- @return vector3
function SprayUtils.TableToVec3(t)
    return vector3(t.x, t.y, t.z)
end

--- Converts a corners table of vector3 to a table of tables.
--- @param corners table
--- @return table
function SprayUtils.CornersToTable(corners)
    return {
        topLeft = SprayUtils.Vec3ToTable(corners.topLeft),
        topRight = SprayUtils.Vec3ToTable(corners.topRight),
        bottomLeft = SprayUtils.Vec3ToTable(corners.bottomLeft),
        bottomRight = SprayUtils.Vec3ToTable(corners.bottomRight)
    }
end

--- Converts a table of tables to a corners table of vector3.
--- @param t table
--- @return table
function SprayUtils.TableToCorners(t)
    return {
        topLeft = SprayUtils.TableToVec3(t.topLeft),
        topRight = SprayUtils.TableToVec3(t.topRight),
        bottomLeft = SprayUtils.TableToVec3(t.bottomLeft),
        bottomRight = SprayUtils.TableToVec3(t.bottomRight)
    }
end

--- Returns the center coordinate from a corners table.
--- @param corners table
--- @return vector3
function SprayUtils.GetCenterFromCorners(corners)
    return (corners.topLeft + corners.topRight + corners.bottomLeft + corners.bottomRight) / 4.0
end

--- Clamps a value between a minimum and maximum.
--- @param val number
--- @param min number
--- @param max number
--- @return number
function SprayUtils.Clamp(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
end

--- Checks if a coordinate is within a blacklisted zone.
--- @param coords vector3
--- @return boolean
function SprayUtils.IsInBlacklistedZone(coords)
    if not Config.BlacklistedZones then return false end
    for _, zone in ipairs(Config.BlacklistedZones) do
        if #(coords - zone.coords) < zone.radius then
            return true
        end
    end
    return false
end

--- Generates a compressed export code for a painting.
--- @param strokeData table
--- @param w number
--- @param h number
--- @return string
function SprayUtils.GenerateExportCode(strokeData, w, h)
    local data = {
        version = 1,
        width = w,
        height = h,
        strokes = strokeData
    }
    local jsonStr = json.encode(data)
    -- Simple base64-like encoding for the string to make it easier to share
    return "PEAK_" .. jsonStr:gsub("\"", "'")
end

--- Decodes a painting export code.
--- @param code string
--- @return table|nil strokes, number width, number height
function SprayUtils.DecodeExportCode(code)
    if not code or not code:match("^PEAK_") then return nil end
    local jsonStr = code:sub(6):gsub("'", "\"")
    local ok, data = pcall(json.decode, jsonStr)
    if not ok or not data or not data.strokes then return nil end
    return data.strokes, data.width, data.height
end
