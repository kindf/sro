local Class = require "common.class"
local Logger = require "common.logger"

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
---@field hp number
---@field maxHp number
---@field skillCooldown table<number, number>
---@field baseExp number
---@field jobExp number
---@field level number
---@field buffs table
---@field sp number
---@field maxSp number
---@field skillGroupReadyAtMs table
---@field components table
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
    self.hp = 1000
    self.maxHp = 1000
    self.dead = false
    self.skillCooldown = {}
    self.baseExp = 0
    self.jobExp = 0
    self.level = 1
    self.buffs = {}

    self.sp = 100
    self.maxSp = 100

    -- 按组号记录本单位可再次使用该组技能的场景时刻，单位为毫秒。
    self.skillGroupReadyAtMs = {}

    self.components = {}
end

function SceneUnit:AttachComponent(componentType, ...)
    assert(not self.components[componentType], "component already attached")
    local component = componentType.new(self, ...)
    self.components[componentType] = component
    return component
end

function SceneUnit:GetComponent(componentType)
    return self.components[componentType]
end

function SceneUnit:UpdateAI(scene, now, events)
end

function SceneUnit:IsPlayer()
    return true
end

function SceneUnit:IsMonster()
    return false
end

function SceneUnit:AddHatred(uid, threat, now)
    Logger.Error("Unit 没有仇恨机制")
end
function SceneUnit:Pack()
    return {
        uid = self.uid,
        x = self.x,
        y = self.y,
        z = self.z,
        common = (self.face or 0) | (self.moving and (1 << 30) or 0),
        hp = self.hp,
        maxHp = self.maxHp
    }
end



return SceneUnit