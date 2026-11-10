local Class = require "common.class"
local SceneUnit = require "scene.scene_unit"
local Logger = require "common.logger"

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
    self.units[uid] = unit
end

function Scene:Leave(uid)
    self.units[uid] = nil
end

function Scene:Move(uid, moveContent)
    local unit = self.units[uid]
    if not unit then
        Logger.Warning("[Scene]Move: uid:%s not found in scene", tostring(uid))
        return
    end
    local dx, dy, dz, time = moveContent.dx, moveContent.dy, moveContent.dz, moveContent.time
    if not dx or (dx < -10000 or dx > 10000) then dx = 0 end
    if not dy or (dy < -10000 or dy > 10000) then dy = 0 end
    if not dz then dz = 0 end
    if not time then time = 0 end
    if time < 0 then time = 0 end
    if time > 2 then time = 2 end

    unit.x = dx
    unit.y = dy
    unit.z = dz
    return {
        dx = dx,
        dy = dy,
        dz = dz,
        time = time
    }
end

function Scene:GetUnit(uid)
    return self.units[uid]
end

return Scene