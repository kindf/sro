
local BleedEffect = class("BleedEffect")

function BleedEffect:Ctor(cfg)
    self.cfg = cfg
end

function BleedEffect:GetCfg()
    return self.cfg
end

function BleedEffect:Update(battle, target)
    local eTime = battle:GetExpireTime()
    if self.nextTakeTime >= eTime then
        return
    end
    self.nextTakeTime = battle:GetExpireTime() + self.cfg.time_interval
    target:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT):DoDamage(battle, self.cfg.value)
end

local Bleed = class("Bleed")
function Bleed:Create(config, battle)
    return BleedEffect.new(config)
end

return Bleed
