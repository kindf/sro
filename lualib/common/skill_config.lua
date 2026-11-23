local SkillConfig = {}

-- 按技能定义的等级顺序取得效果 ID；缺少定义、等级或对应槽位时返回 nil。
function SkillConfig.GetEffectId(skill, level)
    if not skill or not skill.EffectIDs or type(level) ~= "number" then
        return nil
    end

    local rank = math.tointeger(level)
    if not rank or rank < 1 then
        return nil
    end

    return skill.EffectIDs[rank]
end

return SkillConfig