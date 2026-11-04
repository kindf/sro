
local SetAbnormalStateEffect = class("SetAbnormalStateEffect")

function SetAbnormalStateEffect:Ctor(battle, cfg)
    self.cfg = cfg
end

function SetAbnormalStateEffect:GetCfg()
    return self.cfg
end

function SetAbnormalStateEffect:Install(battle, target)
    local stateComponent = target:GetComponent(Define.COMPONENT_TYPE.STATE_COMPONENT)
    stateComponent:SetStateForever(self.cfg.statetype)
end

function SetAbnormalStateEffect:Uninstall(battle, target)
    local stateComponent = target:GetComponent(Define.COMPONENT_TYPE.STATE_COMPONENT)
    stateComponent:ClearState(self.cfg.statetype)
end

local SetAbnormalState = class("SetAbnormalState")

function SetAbnormalState:Create(config, battle)
    return SetAbnormalStateEffect.new(battle, config)
end

return SetAbnormalState
