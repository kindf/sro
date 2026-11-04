local ConfigHelper = require "config.config_helper"
local Define = require "define.define"
local BaseTriggerEffect = class("BaseTriggerEffect")

local triggerRule2Event = {
    ["BeforeAttack"] = Define.BATTLE_EVENT.ENTITY_BEFORE_ATTACK_EVENT,
    ["BattleStart"] = Define.BATTLE_EVENT.BATTLE_START_EVENT,
    ["BeforeDoDmg"] = Define.BATTLE_EVENT.ENTITY_BEFORE_DO_DAMAGE_EVENT,
    ["BeforeBeAttacked"] = Define.BATTLE_EVENT.ENTITY_BEFORE_BE_ATTACK_EVENT,
    ["BeforeDmg"] = Define.BATTLE_EVENT.ENTITY_BEFORE_DAMAGE_EVENT,
    ["AfterBorn"] = Define.BATTLE_EVENT.ENTITY_AFTER_BORN_EVENT,
}

function BaseTriggerEffect:Ctor(battle, cfg)
    self.nextTriggerTime = 0
end

function BaseTriggerEffect:Install(battle, traget)
    local buffComponent = traget:GetComponent(Define.COMPONENT_TYPE.BUFF_COMPONENT)
    buffComponent:RegisterTrigger(triggerRule2Event[self.cfg.triggerRule._type_], self)
end

function BaseTriggerEffect:Uninstall(battle, traget)
    local buffComponent = traget:GetComponent(Define.COMPONENT_TYPE.BUFF_COMPONENT)
    buffComponent:UnregisterTrigger(triggerRule2Event[self.cfg.triggerRule._type_], self)
end

function BaseTriggerEffect:InCD(battle)
    local eTime = battle:GetExpireTime()
    return eTime < self.nextTriggerTime
end

function BaseTriggerEffect:SetCD(battle)
    self.nextTriggerTime = battle:GetExpireTime() + self.cfg.triggerRule.cd
end

function BaseTriggerEffect:CheckTriggerCondition(battle, entity, param)
    local condition = self.cfg.triggerRule.condition
    return ConfigHelper.GetConfigClass(condition):CheckCondition(condition, battle, entity, param)
end

return BaseTriggerEffect
