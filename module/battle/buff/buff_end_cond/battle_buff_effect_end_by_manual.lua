local BaseBuffEffectEndCond = require "buff.buff_end_cond.base_buff_effect_end_cond"
local ManualBuffEffectEndCond = class("ManualBuffEffectEndCond", BaseBuffEffectEndCond)

function ManualBuffEffectEndCond:IsEnd(_, _)
    return false
end

function ManualBuffEffectEndCond:Cmp(battle, other)
    return self._classname_ == other._classname_ and 1 or 0
end

function ManualBuffEffectEndCond:isEndByManual(_)
    return true
end

local BattleBuffEffectEndByManual = class("BattleBuffEffectEndByManual")
function BattleBuffEffectEndByManual:Create()
    return ManualBuffEffectEndCond.new()
end

return BattleBuffEffectEndByManual

