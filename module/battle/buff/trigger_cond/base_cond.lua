local Define = require "define.define"
local BaseEffectTriggerCond = class("BaseEffectTriggerCond")

local GetTragetTypeHandler = {
    [Define.BUFF_EFFECT_TRIGGER_COND_TARGET_TYPE.SELF] = function(entity, _)
        return entity
    end,
    [Define.BUFF_EFFECT_TRIGGER_COND_TARGET_TYPE.ATTACKER] = function(_, param)
        return param.attacker
    end,
    [Define.BUFF_EFFECT_TRIGGER_COND_TARGET_TYPE.DEFENDER] = function(_, param)
        return param.target
    end,
}

function BaseEffectTriggerCond:GetTarget(config, entity, param)
    return GetTragetTypeHandler[config.target](entity, param)
end

return BaseEffectTriggerCond
