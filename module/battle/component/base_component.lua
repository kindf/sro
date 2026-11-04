
local BaseComponent = class("BaseComponent")

function BaseComponent:Ctor()
    self.owner = nil
end

function BaseComponent:SetOwner(owner)
    assert(owner, "owner 不能为空")
    self.owner = owner
end

function BaseComponent:Update(_, _)
end

function BaseComponent:PostUpdate(_, _)
end

function BaseComponent:OnAttach(_)
end

function BaseComponent:OnDetach()
    self.owner = nil
end

function BaseComponent:Pack()
end

return BaseComponent
