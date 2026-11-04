local EntityAttr = class("EntityAttr")

function EntityAttr:Ctor()
    self.attrMap = {}
end

function EntityAttr:OnCreate()
end

function EntityAttr:GetAttr(attrId)
    return self.attrMap[attrId] or 0
end

function EntityAttr:SetAttr(attrId, value)
    assert(value > 0, "不能直接设置非正数，应通过GetAttr DecAttr将属性减为0")
    self.attrMap[attrId] = value
end

function EntityAttr:Reset()
    self.attrMap = {}
end

function EntityAttr:AddAttr(attrId, value)
    if value <= 0 then
        return
    end
    local v = self.attrMap[attrId] or 0
    v = v + value
    if v <= 0 then
        v = nil
    end
    self.attrMap[attrId] = v
end

function EntityAttr:DecAttr(attrId, value)
    if value <= 0 then
        return
    end
    local v = self.attrMap[attrId] or 0
    v = v - value
    if v <= 0 then
        v = nil
    end
    self.attrMap[attrId] = v
end

function EntityAttr:AddFrom(other)
    local otherAttrs = other.attrMap or {}
    for k, v in pairs(otherAttrs) do
        self:AddAttr(k, v)
    end
end

function EntityAttr:MulFrom(other)
    local otherAttrs = other.attrMap or {}
    for k, v in pairs(otherAttrs) do
        local selfAttrV = self:GetAttr(k)
        selfAttrV = math.floor(selfAttrV * (1000 + v) * 0.001)
        self.attrMap[k] = selfAttrV
    end
end

function EntityAttr:CopyFrom(src)
    if not src then
        return
    end
    for k, v in pairs(src) do
        self.attrMap[k] = v
    end
end

return EntityAttr
