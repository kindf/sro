local Define = require "define.define"
local HitAction = require "hit_action.hit_action"
local AttackHitAction = class("AttackHitAction", HitAction)
local function CalcAddAnger(attack, cfgAdd)
    if not attack or cfgAdd == 0 then
        return 0
    end
    local attackSpeed = attack:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT):GetAttr(Define.ENTITY_ATTR.ATTACK_SPEED)
    if attackSpeed > 0 then
        local maxAdd = Data.TBBattleParam.beAttackedAddAngerMax
        local delta = math.floor(cfgAdd / attackSpeed)
        return math.min(maxAdd, delta)
    end
    return 0
end

local function Attack(battle, attackEntity, targetEntity, skillId, skillDamageRate, addAnger)
    local targetAttrComponent = targetEntity:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT)
    local attackAttrComponent = attackEntity:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT)
    local crit = attackAttrComponent:GetAttr(Define.ENTITY_ATTR.CRIT) +
        attackAttrComponent:GetAttr(Define.ENTITY_ATTR.CRIT_ADD)
    -- TODO: 伪随机
    local isCrit = math.random(1, 10000) <= crit
    local cirtDamageRage = 1
    if isCrit then
        cirtDamageRage = attackAttrComponent:GetAttr(Define.ENTITY_ATTR.CRIT_DAMAGE) +
            attackAttrComponent:GetAttr(Define.ENTITY_ATTR.CRIT_DAMAGE_ADD)
        cirtDamageRage = math.min(cirtDamageRage, Data.TBBattleParam.maxCirtRate)
        cirtDamageRage = cirtDamageRage * 0.0001
    end
    local damageInfo = {
        attacker = attackEntity:GetId(),
        target = targetEntity:GetId(),
        crit = isCrit,
        isCrit = isCrit,
        subDmg = 0,
        def = 0,
        defSubRate = 0,
        attack = 0,
        addDmg = 0,
        skillDmgRate = 0,
        dmg = 0,
        finalDmg = 0,
        cirtDmgRate = cirtDamageRage,
    }
    local subDmg = targetAttrComponent:GetAttr(Define.ENTITY_ATTR.SUB_DAM) * 0.0001
    local def = targetAttrComponent:GetAttr(Define.ENTITY_ATTR.DEF)
    local defSubRate = math.min(Data.TBBattleParam.maxDefSubDmg,
        def / (def * targetEntity:GetLevel() * Data.TBBattleParam.lvSubDmgConst + Data.TBBattleParam.normalSubDmgConst))
    local attack = attackAttrComponent:GetAttr(Define.ENTITY_ATTR.ATT)
    local addDmg = attackAttrComponent:GetAttr(Define.ENTITY_ATTR.ADD_DAM) * 0.0001
    local formulaDmg = attack * skillDamageRate * cirtDamageRage * (1 - defSubRate) * math.max(0, 1 + addDmg) *
        math.max(0, 1 - subDmg)
    damageInfo.subDmg = subDmg
    damageInfo.def = def
    damageInfo.defSubRate = defSubRate
    damageInfo.attack = attack
    damageInfo.addDmg = addDmg
    damageInfo.skillDmgRate = skillDamageRate
    formulaDmg = math.floor(formulaDmg)
    local eventParam = {
        attacker = attackEntity,
        target = targetEntity,
        skillId = skillId,
        dmg = formulaDmg,
        battle = battle,
    }

    if attackEntity then
        attackEntity:FireEvent(Define.BATTLE_EVENT.ENTITYBEFORE_ATTACK_EVENT, eventParam)
    end
    targetEntity:FireEvent(Define.BATTLE_EVENT.ENTITY_BEFORE_BE_ATTACK_EVENT, eventParam)
    if attackEntity then
        attackEntity:FireEvent(Define.BATTLE_EVENT.ENTITY_BEFORE_DO_DAMAGE_EVENT, eventParam)
    end
    targetEntity:FireEvent(Define.BATTLE_EVENT.ENTITY_BEFORE_DAMAGE_EVENT, eventParam)
    local dmg = formulaDmg * (1 + (eventParam.addDmgRate or 0) * 0.0001) + (eventParam.addDmg or 0)
    dmg = math.max(math.floor(dmg), 1)

    local beAttackAction = {
        entityId = targetEntity:GetId(),
        dmg = dmg,
        finalDmg = 0,
        attackerId = attackEntity:GetId(),
        skillId = skillId,
        isCrit = isCrit,
    }

    battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_BE_ATTACKED_HIT_ACTION, beAttackAction)
    local finalDmg = targetEntity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT):DoDamage(battle, dmg)
    damageInfo.dmg = dmg
    damageInfo.finalDmg = finalDmg
    damageInfo.formulaDmg = formulaDmg
    beAttackAction.finalDmg = finalDmg
    if addAnger > 0 then
        local maxAdd = Data.TBBattleParam.beAttackedAddAngerMax
        addAnger = math.min(maxAdd, addAnger)
        targetEntity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT):AddMp(battle, addAnger)
    end
    battle:FireEvent(Define.BATTLE_EVENT.ENTITY_DAMAGE_INFO_EVENT, damageInfo)
end

function AttackHitAction:_OnDoAction(config, battle, attackEntity, targetEntity, skillEffect)
    local maxLvDamage = #config.damage
    local skillDamageRate = (config.damage[skillEffect.skillLevel] and config.damage[skillEffect.skillLevel] or config.damage[maxLvDamage]) *
        0.0001
    local len = #config.beAttackedAddAnger
    local add = (config.beAttackedAddAnger[len] or config.beAttackedAddAnger[len]) or 0
    local addAnger = CalcAddAnger(attackEntity, add)
    Attack(battle, attackEntity, targetEntity, skillEffect.skillId, skillDamageRate, addAnger)
end

return AttackHitAction
