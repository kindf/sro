local Define = require "define.define"
local BaseTriggerEffect = require "buff.buff_effect.base_trigger_effect"
local DamageReductionEffect = class("DamageReductionEffect", BaseTriggerEffect)

function DamageReductionEffect:Ctor(battle, cfg)
    self.cfg = cfg
end

function DamageReductionEffect:GetCfg()
    return self.cfg
end

function DamageReductionEffect:Install(battle, target)
    local buffComponent = target:GetComponent(Define.COMPONENT_TYPE.BUFF_COMPONENT)
    buffComponent:RegisterTrigger(Define.BATTLE_EVENT.ENTITY_BEFORE_DAMAGE_EVENT, self)
end

function DamageReductionEffect:Uninstall(battle, target)
    local buffComponent = target:GetComponent(Define.COMPONENT_TYPE.BUFF_COMPONENT)
    buffComponent:UnregisterTrigger(Define.BATTLE_EVENT.ENTITY_BEFORE_DAMAGE_EVENT, self)
end

function DamageReductionEffect:TakeEffect(battle, target, param)
    if not param then
        return
    end
    local addRate = (param.addDagRate or 0) + self.cfg.proportion
    param.addDagRate = addRate
end

function DamageReductionEffect:InCD(battle)
    return false
end

function DamageReductionEffect:SetCD(battle)
end

local DamageReduction = class("DamageReduction")
function DamageReduction:Create(config, battle)
    return DamageReductionEffect.new(battle, config)
end

return DamageReduction
