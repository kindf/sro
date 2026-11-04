local BaseBuffEffectEndCond = require "buff.buff_end_cond.base_buff_effect_end_cond"

local TransientBuffEffectEndCond = class("TransientBuffEffectEndCond", BaseBuffEffectEndCond)

function TransientBuffEffectEndCond:IsEndByTransient()
    return true
end

function TransientBuffEffectEndCond:IsEnd(_, _)
    return true
end

function TransientBuffEffectEndCond:Cmp(battle, other)
    return self._classname_ == other._classname_ and 1 or 0
end

local BattleBuffEffectEndByTransient = class("BattleBuffEffectEndByTransient")
function BattleBuffEffectEndByTransient:Create()
    return TransientBuffEffectEndCond.new()
end

return BattleBuffEffectEndByTransient
