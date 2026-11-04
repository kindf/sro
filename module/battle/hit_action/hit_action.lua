local ConfigHelper = require "config.config_helper"
local Define = require "define.define"
local Buff = require "buff.buff"

local HitAction = class("HitAction")
function HitAction:DoAction(config, battle, entity, skillEffect)
    if not skillEffect.hitZone then
        return
    end

    local moveComponent = entity:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT)
    local selfPos = moveComponent:GetPosition()
    local idList = ConfigHelper.GetConfigClass(skillEffect.hitZone):SearchEntity(skillEffect.hitZone, battle, selfPos,entity, Define.ENTITY_TYPE.ENTITY, skillEffect.targetId)
    assert(idList and next(idList), "没有搜寻到目标")
    battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_ATTACK_HIT_ACTION, {
        entityId = entity:GetId(),
        targetIds = idList,
        skillId = skillEffect.skillId,
        hitActionIdx = skillEffect.hitActionIdx,
    })
    local prevBuffId = config.prevBuff
    local succBuffId = config.succBuff
    local attackHitAction = {
        attackerId = entity:GetId(),
        targetIds = idList,
        skillId = skillEffect.skillId,
        hitActionIdx = skillEffect.hitActionIdx,
        skillLevel = skillEffect.level,
        prevBuffId = prevBuffId,
        succBuffId = succBuffId,
    }
    battle:FireEvent(Define.BATTLE_EVENT.ENTITY_ATTACK_HIT_EVENT, attackHitAction)
    for _, id in pairs(idList) do
        local buffList = {}
        local targetEntity = battle:GetEntityById(id)
        if prevBuffId ~= 0 then
            local buffObj = Buff.InstallSkillHitPoint(battle, prevBuffId, skillEffect.level, entity, targetEntity)
            table.insert(buffList, buffObj)
        end
        local isOk = self:_OnDoAction(config, battle, entity, targetEntity, skillEffect)
        if isOk and succBuffId ~= 0 then
            local buffObj = Buff.InstallSkillHitPoint(battle, succBuffId, skillEffect.level, entity, targetEntity)
            table.insert(buffList, buffObj)
        end
        for _, buff in ipairs(buffList) do
            buff:RemoveByAttackEnd()
        end
    end
end

function HitAction:_OnDoAction(config, battle, attackEntity, targetEntity, skillEffect)
end

return HitAction
