local ConfigHelper = require "config.config_helper"
local Define = require "define.define"
local BaseComponent = require "component.base_component"
local BuffComponent = class("BuffComponent", BaseComponent)

function BuffComponent:Ctor()
    BaseComponent.Ctor(self)
    self.effectByGroup = {}
    self.trigger = {}
    self.triggerEventHandler = {}
    self.updates = {}
    self.onUpdating = false
end

function BuffComponent:Update(battle, dt)
    if not next(self.effectByGroup) then
        return
    end
    self.onUpdating = true
    for _, v in pairs(self.updates) do
        v:Update(battle, self.owner)
    end
    local removeList = {}
    for k, v in pairs(self.effectByGroup) do
        if ConfigHelper.GetConfigClass(v.endCond):IsEnd(v.endCond, battle) then
            removeList[k] = true
        end
    end
    for k in pairs(removeList) do
        self:_RemoveBuff(battle, k)
    end
    self.onUpdating = false
end

function BuffComponent:_AddEffect(battle, newEffect)
    local oldEffect = self.effectByGroup[newEffect.groupId]
    if oldEffect then
        self:_OnAddEffect(battle, newEffect)
        return
    end
    local oldEffectCfg = oldEffect:GetCfg()
    local newEffectCfg = newEffect:GetCfg()
    if oldEffectCfg.priority > newEffectCfg.priority then
        return
    end

    local oldEndCond = oldEffect.endCond
    local newEndCond = newEffect.endCond
    if oldEffectCfg.id == newEffectCfg.id then
        -- TODO: 什么意思?
        oldEffect.overlay = oldEffect.overlay
        newEffect.overlay = newEffect.overlay
        local newOverlay = newEffect.overlay + oldEffect.overlay
        if newOverlay <= newEffectCfg.maxoverlay then
            newEffect.overlay = newOverlay
            self:_OnReplaceEffect(battle, oldEffect, newEffect)
        else
            newEffect.overlay = newEffectCfg.maxoverlay
            if ConfigHelper.GetConfigClass(newEndCond):Cmp(newEndCond, oldEndCond) > 1 then
                self:_OnReplaceEffect(battle, oldEffect, newEffect)
            end
        end
    else
        if ConfigHelper.GetConfigClass(newEndCond):Cmp(newEndCond, battle, oldEndCond) > 1 then
            self:_OnReplaceEffect(battle, oldEffect, newEffect)
        end
    end
end

function BuffComponent:_OnAddEffect(battle, effect)
    self.effectByGroup[effect.groupId] = effect
    effect:Install(battle, self.owner)
    battle:FireEvent(Define.BATTLE_EVENT.ENTITY_ADD_BUFF_EFFECT_EVENT, {
        battle = battle,
        entityId = self.owner:GetId(),
        effect = effect,
    })
    if effect.Update then
        self.updates[effect.groupId] = effect
    end
    battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_ADD_BUFF_EFFECT_ACTION, {
        entityId = self.owner:GetId(),
        effectId = effect:GetCfg().id,
        overlay = effect.overlay,
    })
end

function BuffComponent:_OnReplaceEffect(battle, oldEffect, newEffect)
    oldEffect:Uninstall(battle, self.owner)
    battle:FireEvent(Define.BATTLE_EVENT.ENTITY_REPLACE_BUFF_EFFECT_EVENT, {
        battle = battle,
        entityId = self.owner:GetId(),
        effect = oldEffect,
    })
    self.effectByGroup[oldEffect.groupId] = nil
    if oldEffect.Update then
        self.updates[oldEffect.groupId] = nil
    end
    self.effectByGroup[newEffect.groupId] = newEffect
    if newEffect.Update then
        self.updates[newEffect.groupId] = newEffect
    end

    newEffect:Install(battle, self.owner)
    battle:FireEvent(Define.BATTLE_EVENT.ENTITY_REPLACE_BUFF_EFFECT_EVENT, {
        entityId = self.owner:GetId(),
        effectId = newEffect:GetCfg().id,
        overlay = newEffect.overlay,
    })
    battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_UPDATE_BUFF_EFFECT_ACTION, {
        entityId = self.owner:GetId(),
        effectId = newEffect:GetCfg().id,
        overlay = newEffect.overlay,
    })
end

function BuffComponent:_RemoveBuff(battle, groupId)
    local effect = self.effectByGroup[groupId]
    if not effect then
        return
    end
    effect:Uninstall(battle, self.owner)
    battle:FireEvent(Define.BATTLE_EVENT.ENTITY_REMOVE_BUFF_EFFECT_EVENT, {
        battle = battle,
        entityId = self.owner:GetId(),
        effect = effect,
    })
    if effect.Update then
        self.updates[groupId] = nil
    end
    self.effectByGroup[groupId] = nil
    battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_REMOVE_BUFF_EFFECT_ACTION, {
        entityId = self.owner:GetId(),
        effectId = effect:GetCfg().id,
    })
end

function BuffComponent:RegisterTrigger(eventId, effect)
    local tragetEventTrigger = self.trigger[eventId]
    if not tragetEventTrigger then
        tragetEventTrigger = {}
        self.trigger[eventId] = tragetEventTrigger
    end
    tragetEventTrigger[effect] = true
    local cancleF = self.triggerEventHandler[eventId]
    if not cancleF then
        cancleF = self.owner:RegisterEventHandler(eventId, self, "_OnEvent")
        self.triggerEventHandler[eventId] = cancleF
    end
end

function BuffComponent:UnregisterTrigger(eventId, effect)
    local tragetEventTrigger = self.trigger[eventId]
    if not tragetEventTrigger then
        return
    end
    tragetEventTrigger[effect] = nil
    if not next(tragetEventTrigger) then
        local cancleF = self.triggerEventHandler[eventId]
        if cancleF then
            cancleF()
        end
    end
end

function BuffComponent:_OnEvent(eventType, param)
    local battle = param.battle
    local tragetEventTrigger = self.trigger[eventType]
    if not tragetEventTrigger then
        return
    end
    for k in pairs(tragetEventTrigger) do
        if not k:InCD(battle) and k:CheckTriggerCondition(battle, self, param) then
            k:TakeEffect(battle, self, param)
            k:SetCD(battle)
        end
    end
end

return BuffComponent
