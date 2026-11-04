local HitAction = require "hit_action.hit_action"
local Buff = require "buff.buff"

local BuffHitAction = class("BuffHitAction", HitAction)
function BuffHitAction:_OnDoAction(config, battle, attacker, entity, skillEffect)
    local skillLevel = skillEffect.level
    local maxBuffCount = #self.buffId
    local buffId = self.buffId[skillLevel] or self.buffId[maxBuffCount]
    Buff.InstallSkillHitPoint(battle, buffId, skillLevel, attacker, entity)
end

return BuffHitAction

