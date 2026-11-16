local Class = require "common.class"
local SceneUnit = require "scene.scene_unit"

---@class DropUnit:SceneUnit
local DropUnit = Class("DropUnit", SceneUnit)

function DropUnit:Ctor(itemId, count, x, z)
    SceneUnit.Ctor(self)
    self.itemId = itemId
    self.count = count or 1
    self.x = x
    self.z = z
end

function DropUnit:Pack()
    local pack = SceneUnit.Pack(self)
    pack.unitType = 2
    pack.entityId = self.itemId
    pack.count = self.count
    return pack
end

function DropUnit:IsPlayer()
    return false
end

function DropUnit:IsDrop()
    return true
end

return DropUnit