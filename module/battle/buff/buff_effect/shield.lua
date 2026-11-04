
local ShieldEffect = class("ShieldEffect")

function ShieldEffect:Ctor(battle, cfg)
    self.cfg = cfg
    self.value = self.cfg.shieldvalue
end

function ShieldEffect:GetCfg()
    return self.cfg
end

function ShieldEffect:TakeEffect(battle, target, param)
    if self.value <= 0 then
        return
    end
    local damage = math.max(param.dmg - self.value, 0)
    self.value = self.value - param.dmg + damage
    param.dmg = damage
end

local Shield = class("Shield")

function Shield:Create(config, battle)
    return ShieldEffect.new(battle, config)
end

return Shield
