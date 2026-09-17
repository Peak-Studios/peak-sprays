import { LuaFactory } from 'wasmoon'
import fs from 'node:fs'
import path from 'node:path'

/**
 * Creates and initializes a Lua VM pre-populated with FiveM native and runtime stubs.
 */
export async function createLuaEnvironment(options = {}) {
  const factory = new LuaFactory()
  const lua = await factory.createEngine()

  // Storage for callbacks and registered net events
  const callbacks = new Map()
  const netEvents = new Map()
  const clientEventsSent = []
  const dbState = {
    paintings: new Map(),
    designs: new Map(),
    lastInsertId: 100,
  }

  // FiveM math & vector types
  lua.global.set('vector3', (x, y, z) => ({
    x: Number(x) || 0,
    y: Number(y) || 0,
    z: Number(z) || 0,
  }))

  lua.global.set('norm', (v) => {
    const len = Math.sqrt((v.x || 0) ** 2 + (v.y || 0) ** 2 + (v.z || 0) ** 2) || 1
    return { x: (v.x || 0) / len, y: (v.y || 0) / len, z: (v.z || 0) / len }
  })

  lua.global.set('cross', (a, b) => ({
    x: (a.y || 0) * (b.z || 0) - (a.z || 0) * (b.y || 0),
    y: (a.z || 0) * (b.x || 0) - (a.x || 0) * (b.z || 0),
    z: (a.x || 0) * (b.y || 0) - (a.y || 0) * (b.x || 0),
  }))

  // JSON serializer in JS
  lua.global.set('__json_encode_js', (val) => {
    try {
      return JSON.stringify(val)
    } catch {
      return '{}'
    }
  })

  // FiveM json library implemented in Lua to produce native tables
  lua.doString(`
    local function _parse_json(str)
      if type(str) ~= "string" or #str == 0 then return nil end
      local pos = 1
      local len = #str
      local function skip_ws()
        while pos <= len and str:byte(pos) <= 32 do pos = pos + 1 end
      end
      local parse_val
      local function parse_str()
        pos = pos + 1
        local buf = {}
        local start = pos
        while pos <= len do
          local c = str:sub(pos, pos)
          if c == '"' then
            table.insert(buf, str:sub(start, pos - 1))
            pos = pos + 1
            return table.concat(buf)
          elseif c == '\\\\' then
            table.insert(buf, str:sub(start, pos - 1))
            local esc = str:sub(pos + 1, pos + 1)
            if esc == 'n' then table.insert(buf, "\\n")
            elseif esc == 't' then table.insert(buf, "\\t")
            elseif esc == 'r' then table.insert(buf, "\\r")
            elseif esc == '"' then table.insert(buf, '"')
            elseif esc == '\\\\' then table.insert(buf, '\\\\')
            else table.insert(buf, esc) end
            pos = pos + 2
            start = pos
          else
            pos = pos + 1
          end
        end
        return table.concat(buf)
      end
      local function parse_num()
        local start = pos
        if str:sub(pos, pos) == '-' then pos = pos + 1 end
        while pos <= len and ((str:byte(pos) >= 48 and str:byte(pos) <= 57) or str:sub(pos, pos) == '.' or str:sub(pos, pos) == 'e' or str:sub(pos, pos) == 'E' or str:sub(pos, pos) == '+' or str:sub(pos, pos) == '-') do
          pos = pos + 1
        end
        return tonumber(str:sub(start, pos - 1))
      end
      local function parse_arr()
        pos = pos + 1
        local arr = {}
        skip_ws()
        if str:sub(pos, pos) == ']' then pos = pos + 1 return arr end
        while true do
          table.insert(arr, parse_val())
          skip_ws()
          local c = str:sub(pos, pos)
          if c == ']' then pos = pos + 1 break
          elseif c == ',' then pos = pos + 1
          else break end
        end
        return arr
      end
      local function parse_obj()
        pos = pos + 1
        local obj = {}
        skip_ws()
        if str:sub(pos, pos) == '}' then pos = pos + 1 return obj end
        while true do
          skip_ws()
          if str:sub(pos, pos) ~= '"' then break end
          local key = parse_str()
          skip_ws()
          if str:sub(pos, pos) == ':' then pos = pos + 1 end
          local val = parse_val()
          obj[key] = val
          skip_ws()
          local c = str:sub(pos, pos)
          if c == '}' then pos = pos + 1 break
          elseif c == ',' then pos = pos + 1
          else break end
        end
        return obj
      end
      parse_val = function()
        skip_ws()
        local c = str:sub(pos, pos)
        if c == '"' then return parse_str()
        elseif c == '{' then return parse_obj()
        elseif c == '[' then return parse_arr()
        elseif c == 't' and str:sub(pos, pos + 3) == 'true' then pos = pos + 4 return true
        elseif c == 'f' and str:sub(pos, pos + 4) == 'false' then pos = pos + 5 return false
        elseif c == 'n' and str:sub(pos, pos + 3) == 'null' then pos = pos + 4 return nil
        else return parse_num() end
      end
      return parse_val()
    end

    json = {
      encode = function(v) return __json_encode_js(v) end,
      decode = function(s) return _parse_json(s) end
    }
  `)

  // Basic FiveM scheduler and logging
  lua.global.set('print', (...args) => {
    if (options.debug) console.log('[Lua]', ...args)
  })
  lua.global.set('GetGameTimer', () => Date.now())
  lua.global.set('Wait', () => {})
  lua.global.set('SetTimeout', (ms, fn) => {
    // Immediate or deferred stub
  })
  lua.global.set('CreateThread', (fn) => {
    if (options.runThreads !== false && typeof fn === 'function') {
      try { fn() } catch (e) { if (options.debug) console.error('[Lua Thread Error]', e) }
    }
  })

  lua.global.set('GetCurrentResourceName', () => 'peak-sprays')
  lua.global.set('GetPlayerPed', (src) => src || 1)
  lua.global.set('GetEntityCoords', (ped) => ({ x: 100.0, y: 200.0, z: 30.0 }))
  lua.global.set('PlayerPedId', () => 1)

  lua.global.set('TriggerClientEvent', (eventName, target, ...args) => {
    clientEventsSent.push({ eventName, target, args })
    if (options.debug) console.log('[TriggerClientEvent]', eventName, target, args)
  })

  lua.global.set('TriggerEvent', (eventName, ...args) => {
    const handler = netEvents.get(eventName)
    if (handler) handler(...args)
  })

  lua.global.set('RegisterNetEvent', (eventName, fn) => {
    netEvents.set(eventName, fn)
  })

  lua.global.set('AddEventHandler', (eventName, fn) => {
    netEvents.set(eventName, fn)
  })

  // Base Peak tables
  lua.doString(`
    Peak = {
      Utils = {},
      Server = {},
      Client = {}
    }
    SprayUtils = {}
    Config = {
      Debug = false,
      DefaultColor = "#000000",
      CanvasWidth = 1024,
      CanvasHeight = 1024,
      MaxStrokesPerPainting = 500,
      MaxPointsPerStroke = 5000,
      MaxTotalPoints = 50000,
      MaxLayersPerComposition = 32,
      ImageSpraysEnabled = true,
      ImageDefaultSize = 256,
      ImageMinScale = 0.25,
      ImageMaxScale = 4.0,
      ImageMaxPerSpray = 5,
      ImageUrlMaxLength = 512,
      ImageAllowedHosts = { "i.imgur.com", "media.discordapp.net", "cdn.discordapp.com", "images.unsplash.com" },
      SelectionMaxDistance = 10.0,
      SprayPaintItem = "spray_paint",
      ClothItem = "spray_cloth",
      ColoredItems = {
        spray_paint_red = "#EF4444",
        spray_paint_blue = "#3B82F6"
      },
      ConsumeSprayOnValidate = true,
      ConsumeClothOnValidate = true,
      ExpiryEnabled = false
    }
  `)

  // Vector math with FiveM-like operators in pure Lua
  lua.doString(`
    local vecMeta = {
      __sub = function(a, b)
        return vector3(a.x - b.x, a.y - b.y, a.z - b.z)
      end,
      __add = function(a, b)
        return vector3(a.x + b.x, a.y + b.y, a.z + b.z)
      end,
      __len = function(v)
        return math.sqrt((v.x or 0)^2 + (v.y or 0)^2 + (v.z or 0)^2)
      end,
      __tostring = function(v)
        return string.format("vector3(%f, %f, %f)", v.x or 0, v.y or 0, v.z or 0)
      end
    }

    vector3 = function(x, y, z)
      local v = { x = tonumber(x) or 0, y = tonumber(y) or 0, z = tonumber(z) or 0 }
      return setmetatable(v, vecMeta)
    end

    promise = {}
    promise.__index = promise
    function promise.new()
      local p = { val = nil, resolved = false }
      setmetatable(p, promise)
      return p
    end
    function promise:resolve(v)
      self.val = v
      self.resolved = true
    end

    Citizen = {
      Await = function(p)
        return p.val
      end
    }
  `)

  // MySQL mock hooks
  lua.global.set('__mysql_query', (query, params, cb) => {
    let res = []
    if (options.onQuery) {
      res = options.onQuery(query, params)
    }
    if (typeof cb === 'function') cb(res)
    return res
  })

  lua.global.set('__mysql_insert', (query, params, cb) => {
    let id = ++dbState.lastInsertId
    if (options.onInsert) {
      id = options.onInsert(query, params)
    }
    if (typeof cb === 'function') cb(id)
    return id
  })

  lua.global.set('__mysql_update', (query, params, cb) => {
    let affected = 1
    if (options.onUpdate) {
      affected = options.onUpdate(query, params)
    }
    if (typeof cb === 'function') cb(affected)
    return affected
  })

  lua.doString(`
    MySQL = {
      query = function(q, p, cb)
        local res = __mysql_query(q, p, cb)
        return res
      end,
      insert = function(q, p, cb)
        local res = __mysql_insert(q, p, cb)
        return res
      end,
      update = function(q, p, cb)
        local res = __mysql_update(q, p, cb)
        return res
      end
    }
  `)

  // Register callback bridge in Lua
  lua.doString(`
    __server_callbacks = {}
    function Peak.Server.RegisterCallback(name, fn)
      __server_callbacks[name] = fn
      __registerServerCallback(name, fn)
    end
    function Peak.Client.TriggerCallback(name, ...)
      local fn = __server_callbacks[name]
      if not fn then error("Callback " .. tostring(name) .. " not found") end
      return fn(1, ...)
    end
    function Peak.Server.GetIdentifier(src) return "license:test_" .. tostring(src) end
    function Peak.Server.GetPlayerName(src) return "TestPlayer" .. tostring(src) end
    function Peak.Server.HasItem(src, item, count) return true end
    function Peak.Server.RemoveItem(src, item, count) return true end
    function Peak.Server.AddItem(src, item, count) return true end
    function Peak.Server.CanErase(src) return true end
    function Peak.Server.CanSpray(src) return true end
    function LogPaintCreate(...) end
    function LogPaintErase(...) end
    function LogPaintDelete(...) end
    function LogAdminDelete(...) end
  `)

  lua.global.set('__registerServerCallback', (name, fn) => {
    callbacks.set(name, fn)
  })

  // Load production file helper
  const loadFile = (relPath) => {
    const fullPath = path.resolve(process.cwd(), relPath)
    const code = fs.readFileSync(fullPath, 'utf8')
    return lua.doString(code)
  }

  return {
    lua,
    loadFile,
    callbacks,
    netEvents,
    clientEventsSent,
    dbState,
    setLuaGlobalJson: async (varName, jsObj) => {
      lua.global.set(`__tmp_json_${varName}`, JSON.stringify(jsObj))
      await lua.doString(`${varName} = json.decode(__tmp_json_${varName})`)
    },
    invokeCallback: async (name, src, ...args) => {
      lua.global.set('__cb_args_json', JSON.stringify(args))
      lua.global.set('__cb_name', name)
      lua.global.set('__cb_src', src)
      return await lua.doString(`
        local fn = __server_callbacks[__cb_name]
        if not fn then error("Callback " .. tostring(__cb_name) .. " not found") end
        local args = json.decode(__cb_args_json)
        local unpack = table.unpack or unpack
        return fn(__cb_src, unpack(args))
      `)
    }
  }
}
