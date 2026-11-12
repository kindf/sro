local Class = require "common.class"
local SceneUnit = require "scene.scene_unit"
local Logger = require "common.logger"

local MAX_SPEED       = 6.0   -- 占位，后面从属性表取
local SPEED_TOLERANCE = 2.0   -- 允许 2 倍速度
local TOKEN_MAX       = 2.0   -- 最多攒 2 秒
local TOKEN_REGEN     = 1.0   -- 每秒回 1 秒
local MAX_DT          = 0.5   -- 单次最多补 500ms

---@class Scene
---@field sceneId number
---@field units table<integer, SceneUnit>
local Scene = Class("Scene")

function Scene:Ctor()
    self.sceneId = nil
    self.units = {}
end

function Scene:Enter(uid, x, y, z)
    local unit = SceneUnit.new()
    unit.uid = uid
    unit.x = x
    unit.y = y
    unit.z = z
    unit.lastMoveAt = os.time()
    unit.token = 2.0
    self.units[uid] = unit
end

function Scene:Leave(uid)
    self.units[uid] = nil
end

local function _Finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

---@param unit SceneUnit
local function _ForcedBack(unit)
    return {
        dx = unit.x,
        dy = unit.y,
        dz = unit.z,
        time = 0,
        forced = true,
    }
end

function Scene:Move(uid, moveContent)
    local unit = self.units[uid]
    if not unit then
        Logger.Warning("[Scene]Move: uid:%s not found in scene", tostring(uid))
        return
    end
    local dx, dy, dz, time = moveContent.dx, moveContent.dy, moveContent.dz, moveContent.time
    if not _Finite(dx) or not _Finite(dy) or not _Finite(dz) or not _Finite(time) then
        return _ForcedBack(unit)
    end
    time = math.max(0, math.min(2, time))

    local now = os.time()
    local dt = now - unit.lastMoveAt
    if dt < 0 then dt = 0 end
    if dt > MAX_DT then dt = MAX_DT end

    unit.token = math.min(TOKEN_MAX, unit.token + dt * TOKEN_REGEN)
    local dist = math.sqrt((dx - unit.x)^2 + (dz - unit.z)^2)
    local cost = dist / (MAX_SPEED * SPEED_TOLERANCE)
    if cost > unit.token then
        unit.token = 0
        unit.lastMoveAt = now
        return _ForcedBack(unit)
    end

    unit.x, unit.y, unit.z = dx, dy, dz
    unit.lastMoveAt = now
    unit.token = unit.token - cost
    return {
        dx = dx,
        dy = dy,
        dz = dz,
        time = time,
        forced = false,
    }
end

function Scene:GetUnit(uid)
    return self.units[uid]
end

return Scene