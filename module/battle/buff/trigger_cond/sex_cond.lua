
local BaseEffectTriggerCond = require "buff.trigger_cond.base_cond"
local EffectTriggerCondSex = class("EffectTriggerCondSex", BaseEffectTriggerCond)

function EffectTriggerCondSex:CheckCondition(config, battle, entity, param)
    local target = self:GetTarget(config, entity, param)
    if target then
        return false
    end
    return target:GetSex() == self.sex
end

return EffectTriggerCondSex
