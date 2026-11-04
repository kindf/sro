local ConfigHelper = require "config.config_helper"
local Define = require "define.define"
local Buff = class("Buff")
local BaseNoGroupId = 1 << 20

function Buff:Ctor(target, effectObjs)
    self.target = target
    self.effectObjs = effectObjs
end

function Buff:RemoveByAttackEnd(battle)
    local buffComponent = self.target:GetComponent(Define.COMPONENT_TYPE.BUFF_COMPONENT)
    for _, v in pairs(self.effectObjs) do
        if v.endCond:IsAttackEnd(battle) then
            buffComponent:_RemoveEffect(battle, v.groupId)
        end
    end
end

function Buff.InstallSkillHitPoint(battle, buffId, skillLv, attacker, defender)
    local buffCfg = Data.TBBattleBuff[buffId]
    local target = defender
    if buffCfg.target == Define.ENTITY_RELATION_TYPE.SELF then
        target = attacker
    end

    if target.onUpdating then
        return
    end

    local effectObjs = {}
    local effectCfg = Data.TBBattleBuffEffect
    for _, v in ipairs(buffCfg.effectList) do
        local cfg = effectCfg[v.effectId]
        local rValue = math.random(1, 10000)
        local isHit = rValue <= cfg.hitRate
        if isHit then
            Buff._AddEffect(battle, cfg, v.endCond, target, effectObjs)
        end
    end
    if next(effectObjs) then
        battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_ADD_BUFF_ACTION, {
            entityId = target:GetId(),
            buffId = buffCfg.id,
        })
    end
    return Buff.new(target, effectObjs)
end

function Buff._AddEffect(battle, effectCfg,endCondCfg, target, effectObjs)
    local endCond = ConfigHelper.GetConfigClass(endCondCfg):Create(endCondCfg, battle)
    local effect = ConfigHelper.GetConfigClass(effectCfg):Create(effectCfg, battle, endCond)
    effect.endCond = endCond
    effect.overlay = 1
    effect.groupId = effectCfg.group ~= 0 and effectCfg.group or BaseNoGroupId + effectCfg.id

    -- 是否瞬间结束
    if not endCond:IsEndByTransient(battle) then
        local buffComponent = target:GetComponent(Define.COMPONENT_TYPE.BUFF_COMPONENT)
        buffComponent:_AddEffect(battle, effect)
        table.insert(effectObjs, effect)
    else
        effect:Install(battle, target)
    end
end

function Buff.InstallBuff(battle, buffCfg, target)
    if target.onUpdating then
        return
    end
    local effectObjs = {}
    for _, v in ipairs(buffCfg.effectList) do
        local cfg = Data.TBBattleBuffEffect[v.effectId]
        Buff._AddEffect(battle, cfg, v.endCond, target, effectObjs)
    end
    if next(effectObjs) then
        battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_ADD_BUFF_ACTION, {
            entityId = target:GetId(),
            buffId = buffCfg.id,
        })
    end
    return Buff.new(target, effectObjs)
end


return Buff
