local Class = require "common.class"
local SceneUnit = require "scene.scene_unit"
local Logger = require "common.logger"

local MAX_SPEED       = 6.0   -- 占位，后面从属性表取
local SPEED_TOLERANCE = 2.0   -- 允许 2 倍速度
local TOKEN_MAX       = 2.0   -- 最多攒 2 秒
local TOKEN_REGEN     = 1.0   -- 每秒回 1 秒
local MAX_DT          = 0.5   -- 单次最多补 500ms
local GRID_SIZE = 32       -- 32 米一格
local AOI_RADIUS = 1       -- 3x3
local DEFAULT_MAX_X = 10000 -- 默认地图尺寸
local DEFAULT_MIN_X = -10000-- 默认地图尺寸
local DEFAULT_MAX_Z = 10000-- 默认地图尺寸
local DEFAULT_MIN_Z = -10000-- 默认地图尺寸


---@class Scene
---@field sceneId number
---@field units table<integer, SceneUnit>
---@field grids table<integer, table<integer, boolean>>
local Scene = Class("Scene")

function Scene:Ctor(cfg)
    self.sceneId = cfg.id
    self.units = {}
    self.grids = {}

    self.startPos = cfg.StartPos and cfg.StartPos[1] or {0, 0, 0}
    self.startFace = cfg.StartFace or 0

    local size = cfg.MapSize and cfg.MapSize[1] or 0
    local offset = cfg.MapOffset and cfg.MapOffset[1] or {0, 0}

    if size > 0 then
        self.minX, self.maxX = offset[1], offset[1] + size
        self.minZ, self.maxZ = offset[2], offset[2] + size
    else
        self.minX, self.maxX = -DEFAULT_MIN_X, DEFAULT_MAX_X
        self.minZ, self.maxZ = DEFAULT_MIN_Z, DEFAULT_MAX_Z
    end
end

function Scene:GridKey(gx, gz)
    return gx.."_"..gz
end

---@param unit SceneUnit
function Scene:AddToGrid(unit)
    local gx = math.floor(unit.x / GRID_SIZE)
    local gz = math.floor(unit.z / GRID_SIZE)
    unit.gx, unit.gz = gx, gz

    local key = self:GridKey(gx, gz)
    local set = self.grids[key] or {}
    set[unit.uid] = true
    self.grids[key] = set
end

---@param unit SceneUnit
function Scene:RemoveFromGrid(unit)
    local key = self:GridKey(unit.gx, unit.gz)
    local set = self.grids[key]
    if set then
        set[unit.uid] = nil
        if next(set) == nil then
            self.grids[key] = nil
        end
    end
end

function Scene:GetNeighborSet(gx, gz)
    local result = {}
    for i = gx - AOI_RADIUS, gx + AOI_RADIUS do
        for j = gz - AOI_RADIUS, gz + AOI_RADIUS do
            local key = self:GridKey(i, j)
            local set = self.grids[key]
            if set then
                for uid in pairs(set) do
                    result[uid] = true
                end
            end
        end
    end
    return result
end

function Scene:Enter(uid, x, y, z)
    if not x then
        x, y, z = self.startPos[1], self.startPos[2], self.startPos[3]
    end
    local unit = SceneUnit.new()
    unit.uid = uid
    unit.x = x
    unit.y = y
    unit.z = z
    unit.lastMoveAt = os.time()
    unit.token = TOKEN_MAX
    self.units[uid] = unit

    self:AddToGrid(unit)
    local neighbors = self:GetNeighborSet(unit.gx, unit.gz)
    neighbors[uid] = nil
    local others = {}
    for id, u in pairs(neighbors) do
        table.insert(others, self.units[id]:Pack())
    end

    return unit:Pack(), others
end

function Scene:Leave(uid)
    local unit = self.units[uid]
    if not unit then
        return nil, {}
    end

    local neighbors = self:GetNeighborSet(unit.gx, unit.gz)
    neighbors[uid] = nil

    
    self:RemoveFromGrid(unit)
    self.units[uid] = nil

    local others = {}
    for id, u in pairs(neighbors) do
        table.insert(others, self.units[id]:Pack())
    end

    return unit and unit:Pack(), others
end

local function _Finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

---@param unit SceneUnit
local function _ForcedBack(unit)
    return {
        dx = unit.x, dy = unit.y, dz = unit.z,
        time = 0, forced = true,
        receivers = {}, enters = {}, leaves = {},
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

    if dx < self.minX or dx > self.maxX or dz < self.minZ or dz > self.maxZ then
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

    local oldGx, oldGz = unit.gx, unit.gz
    local newGx, newGz = math.floor(dx / GRID_SIZE), math.floor(dz / GRID_SIZE)
    local oldSet = self:GetNeighborSet(oldGx, oldGz)
    local newSet = self:GetNeighborSet(newGx, newGz)
    oldSet[unit.uid] = nil
    newSet[unit.uid] = nil

    local enters, leaves, receivers = {}, {}, {}
    for id in pairs(newSet) do
        if not oldSet[id] then
            table.insert(enters, self.units[id]:Pack())
        else
            table.insert(receivers, id)
        end
    end
    for id in pairs(oldSet) do
        if not newSet[id] then
            table.insert(leaves, id)
        end
    end

    local common = moveContent.common
    unit.x, unit.y, unit.z = dx, dy, dz
    unit.lastMoveAt = now
    unit.token = unit.token - cost
    unit.face = common & 0xFFFF
    unit.moving = ((common >> 30) & 1) == 1
    self:RemoveFromGrid(unit)
    self:AddToGrid(unit)

    return {
        dx = dx,
        dy = dy,
        dz = dz,
        time = time,
        forced = false,
        receivers = receivers,
        enters = enters,
        leaves = leaves,
    }
end

function Scene:GetUnit(uid)
    return self.units[uid]
end

return Scene