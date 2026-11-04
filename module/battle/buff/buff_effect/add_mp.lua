local Define = require "define.define"
local AddMPEffect = class("AddMPEffect")

function AddMPEffect:Ctor(battle, cfg)
    self.cfg = cfg
end

function AddMPEffect:Install(battle, target)
    local fightComponent = target:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    fightComponent:AddMP(battle, self.cfg.mp)
end

function AddMPEffect:GetCfg()
    return self.cfg
end

function AddMPEffect:Uninstall(battle, target)
end

local AddMP = class("AddMP")

function AddMP:Create(config, battle)
    return AddMPEffect.new(battle, config)
end

return AddMP
