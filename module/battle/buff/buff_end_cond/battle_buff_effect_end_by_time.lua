local BaseBuffEffectEndCond = require "buff.buff_end_cond.base_buff_effect_end_cond"
local TimeBuffEffectEndCond = class("TimeBuffEffectEndCond", BaseBuffEffectEndCond)

function TimeBuffEffectEndCond:Ctor(endTime)
    self.endTime = endTime
end

function TimeBuffEffectEndCond:IsEnd(battle, _)
    return battle:GetExpireTime() >= self.endTime
end

function TimeBuffEffectEndCond:Cmp(battle, other)
    if self._classname_ ~= other._classname_ then
        return 0
    end
    return self.endTime - other.endTime
end

function TimeBuffEffectEndCond:isEndByTime(_)
    return true
end

local BattleBuffEffectEndByTime = class("BattleBuffEffectEndByTime")
function BattleBuffEffectEndByTime:Create(config, battle)
    return TimeBuffEffectEndCond.new(battle:GetExpireTime() + config.duraction)
end

return BattleBuffEffectEndByTime
