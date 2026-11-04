local Define = require "define.define"
local AddAttrEffect = class("AddAttrEffect")

function AddAttrEffect:Ctor(battle, cfg)
    self.cfg = cfg
end

function AddAttrEffect:Install(battle, target)
    local attrComponent = target:GetComponent("AttrComponent")
    for k, v in pairs(self.cfg.attrs) do
        attrComponent:AddAttrBySource(Define.ENTITY_ATTR_SOURCE.BUFF, k, v)
    end
end

function AddAttrEffect:Uninstall(battle, target)
    local attrComponent = target:GetComponent("AttrComponent")
    for k, v in pairs(self.cfg.attrs) do
        attrComponent:RemoveAttrBySource(Define.ENTITY_ATTR_SOURCE.BUFF, k, v)
    end
end

function AddAttrEffect:GetCfg()
    return self.cfg
end

local AddAttr = class("AddAttr")

function AddAttr:Create(config, battle)
    return AddAttrEffect.new(battle, config)
end

return AddAttrEffect
