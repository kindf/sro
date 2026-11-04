local BaseBuffEffectEndCond = require "buff.buff_end_cond.base_buff_effect_end_cond"
local NextAttackBuffEffectEndCond = class("NextAttackBuffEffectEndCond", BaseBuffEffectEndCond)

function NextAttackBuffEffectEndCond:IsEndByAttack()
    return true
end

function NextAttackBuffEffectEndCond:IsEnd()
    return false
end

function NextAttackBuffEffectEndCond:Cmp(battle, other)
    return self._classname_ == other._classname_ and 1 or 0
end

local BattleBuffEffectEndByNextAttack = class("BattleBuffEffectEndByNextAttack")
function BattleBuffEffectEndByNextAttack:Create(config, battle)
    return NextAttackBuffEffectEndCond.new()
end

return BattleBuffEffectEndByNextAttack
