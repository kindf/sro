local Define = require "define.define"
local HitAction = require "hit_action.hit_action"
local HealthHitAction = class("HealthHitAction", HitAction)

function HealthHitAction:_OnDoAction(config, battle, attackEntity, targetEntity, skillEffect)
    local skillLevel = skillEffect.level
    local maxLvDmg = #config.health
    local skillHealthRate = (config.health[skillLevel] and config.health[skillLevel] or config.health[maxLvDmg]) * 0.0001
    local attackAttrComponent = attackEntity:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT)
    local att = attackAttrComponent:GetAttr(Define.ENTITY_ATTR.ATT)
    local cr = attackAttrComponent:GetAttr(Define.ENTITY_ATTR.CURE_RATIO) * 0.0001
    local health = att * skillHealthRate * (1 + cr)
    local realHealth = targetEntity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT):DoHeal(battle, health)
    local healthInfo = {
        attacker = attackEntity:GetId(),
        target = targetEntity:GetId(),
        skillHealThRate = skillHealthRate,
        health = health,
        realHealth = realHealth,
    }
    battle:FireEvent(Define.BATTLE_EVENT.ENTITY_HEALTH_INFO_EVENT, healthInfo)
    battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_HEALTH_ACTION, {
        entityId = targetEntity:GetId(),
        health = health,
        realHealth = realHealth,
    })
end

return HealthHitAction
