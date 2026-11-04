local BaseBuffEffectEndCond = class("BaseBuffEffectEndCond")

function BaseBuffEffectEndCond:IsEnd(_)
    assert(false, "方法未实现")
end

function BaseBuffEffectEndCond:Cmp(_, _)
    assert(false, "方法未实现")
end

function BaseBuffEffectEndCond:IsEndByTransient(_)
    return false
end

function BaseBuffEffectEndCond:IsEndByTime(_)
    return false
end

function BaseBuffEffectEndCond:IsEndByAttack(_)
    return false
end

function BaseBuffEffectEndCond:isEndByManual(_)
    return false
end

return BaseBuffEffectEndCond
