local BaseEffectTriggerCond = require "buff.trigger_cond.base_cond"
local EffectTriggerCondCareer = class("EffectTriggerCondCareer", BaseEffectTriggerCond)
function EffectTriggerCondCareer:CheckCondition(config, battle, entity, param)
    local target = self:GetTarget(config, entity, param)
    if target then
        return false
    end
    return target:GetCareer() == self.career
end

return EffectTriggerCondCareer
