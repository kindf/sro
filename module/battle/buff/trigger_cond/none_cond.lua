
local BaseEffectTriggerCond = require "buff.trigger_cond.base_cond"
local EffectTriggerCondNone = class("EffectTriggerCondNone", BaseEffectTriggerCond)

function EffectTriggerCondNone:CheckCondition(config, battle, entity, param)
    return true
end

return EffectTriggerCondNone
