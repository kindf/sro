
local BaseTriggerEffect = require "buff.buff_effect.base_trigger_effect"
local DamageIncreaseEffect = class("DamageIncreaseEffect", BaseTriggerEffect)

function DamageIncreaseEffect:Ctor(battle, cfg)
    BaseTriggerEffect.Ctor(self, battle, cfg)
    self.cfg = cfg
end

function DamageIncreaseEffect:GetCfg()
    return self.cfg
end

function DamageIncreaseEffect:TakeEffect(battle, target, param)
    if not param then
        return
    end

    local addRate = (param.addDagRate or 0) + self.cfg.proportion
    param.addDagRate = addRate
end

local DamageIncrease = class("DamageIncrease")
function DamageIncrease:Create(config, battle)
    return DamageIncreaseEffect.new(battle, config)
end

return DamageIncrease
