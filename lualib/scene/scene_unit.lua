local Class = require "common.class"

---@class SceneUnit
---@field uid number
---@field x number
---@field y number
---@field z number
---@field face number
---@field moving boolean
---@field lastMoveAt number
---@field token number
---@field gx number
---@field gz number
local SceneUnit = Class("SceneUnit")

function SceneUnit:Ctor()
    self.uid = nil
    self.x = 0
    self.y = 0
    self.z = 0
    self.face = 0
    self.moving = false
    self.lastMoveAt = nil
    self.token = 0
    self.gx = 0
    self.gz = 0
end

function SceneUnit:Pack()
    return {
        uid = self.uid,
        x = self.x,
        y = self.y,
        z = self.z,
        common = (self.face or 0) | (self.moving and (1 << 30) or 0),
    }
end

return SceneUnit