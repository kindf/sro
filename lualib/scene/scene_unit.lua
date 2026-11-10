local Class = require "common.class"

---@class SceneUnit
---@field uid number
---@field x number
---@field y number
---@field z number
---@field face number
---@field moving boolean
---@field lastMoveAt number
local SceneUnit = Class("SceneUnit")

function SceneUnit:Ctor()
    self.uid = nil
    self.x = 0
    self.y = 0
    self.z = 0
    self.face = 0
    self.moving = false
    self.lastMoveAt = nil
end

return SceneUnit