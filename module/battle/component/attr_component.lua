local Define = require "define.define"
local BaseComponent = require "component.base_component"
local EntityAttr = require "attr.entity_attr"
local AttrComponent = class("AttrComponent", BaseComponent)

function AttrComponent:Ctor()
    BaseComponent.Ctor(self)
    self.dirtyAttrs = {}
    self.addList = {}
    self.mulList = {}
    self.tmp = EntityAttr.new()

    self.addList[Define.ENTITY_ATTR_SOURCE.BASE] = EntityAttr.new()
    self.addList[Define.ENTITY_ATTR_SOURCE.BUFF] = EntityAttr.new()
    self.mulList[Define.ENTITY_ATTR_SOURCE.BASE] = EntityAttr.new()
    self.mulList[Define.ENTITY_ATTR_SOURCE.BUFF] = EntityAttr.new()
    self.attrMap = {}
    self.needRefresh = false
end

function AttrComponent:GetAttr(attrId)
    self:RecalcAttr()
    return self:_GetAttr(attrId)
end

function AttrComponent:SetAttrBySource(attrSource, attrId, value)
    local maxId = Define.ENTITY_ATTR.MAX_BASE_ATTR
    if attrId <= maxId then
        local addAttr = self.addList[attrSource]
        if not addAttr then
            return
        end
        addAttr:SetAttr(attrId, value)
    else
        local mulAttr = self.mulList[attrSource]
        if not mulAttr then
            return
        end
        mulAttr:SetAttr(attrId - maxId, value)
    end
    self.needRefresh = true
end

function AttrComponent:AddAttrBySource(attrSource, attrId, value)
    local maxId = Define.ENTITY_ATTR_SOURCE.MAX
    if attrId <= maxId then
        local addAttr = self.addList[attrSource]
        if not addAttr then
            return
        end
        addAttr:AddAttr(attrId, value)
    else
        local mulAttr = self.mulList[attrSource]
        if not mulAttr then
            return
        end
        mulAttr:AddAttr(attrId - maxId, value)
    end
    self.needRefresh = true
end

function AttrComponent:DecAttrBySource(attrSource, attrId, value)
    local maxId = Define.ENTITY_ATTR_SOURCE.MAX
    if attrId <= maxId then
        local addAttr = self.addList[attrSource]
        if not addAttr then
            return
        end
        addAttr:DecAttr(attrId, value)
    else
        local mulAttr = self.mulList[attrSource]
        if not mulAttr then
            return
        end
        mulAttr:DecAttr(attrId - maxId, value)
    end
    self.needRefresh = true
end

function AttrComponent:ResetByAttrSource(attrSource)
    if self.addList[attrSource] then
        self.addList[attrSource]:Reset()
    end
    if self.mulList[attrSource] then
        self.mulList[attrSource]:Reset()
    end
    self.needRefresh = true
end

function AttrComponent:GetAddAttrBySource(attrSource)
    return self.addList[attrSource]
end

function AttrComponent:GetMulAttrBySource(attrSource)
    return self.mulList[attrSource]
end

function AttrComponent:RecalcAttr()
    if not self.needRefresh then
        return
    end
    self:_Reset()
    self.tmp:Reset()
    for _, v in pairs(self.addList) do
        self:_AddFrom(v)
    end
    for _, v in pairs(self.mulList) do
        self.tmp:AddFrom(v)
    end
    self:_MulFrom(self.tmp)
    self.tmp:Reset()
    self.needRefresh = false
end

function AttrComponent:_Reset()
    self.attrMap = {}
end

function AttrComponent:_GetAttr(attrId)
    return self.attrMap[attrId] or 0
end

function AttrComponent:_SetAttr(attrId, value)
    if value == 0 then
        return
    end
    local oldValue = self:_GetAttr(attrId)
    local newValue = oldValue + value
    self.attrMap[attrId] = (newValue == 0) and nil or newValue
end

function AttrComponent:_DecAttr(attrId, value)
    if value <= 0 then
        return
    end
    local oldValue = self:_GetAttr(attrId)
    local newValue = oldValue - value
    self.attrMap[attrId] = (newValue == 0) and nil or newValue
end

function AttrComponent:_AddFrom(other)
    for k, v in pairs(other.attrMap or {}) do
        self:_AddAttr(k, v)
    end
end

function AttrComponent:_MulFrom(other)
    for k, v in pairs(other.attrMap or {}) do
        local selfAttrV = self.attrMap[k] or 0
        selfAttrV = math.floor(selfAttrV * (10000 + v) * 0.0001)
        self:_mulAttr(k, selfAttrV)
    end
end

function AttrComponent:Update(dt)
    self:RecalcAttr()
end

function AttrComponent:_AddAttr(attrId, value)
    if value == 0 then
        return
    end
    local oldValue = self:_GetAttr(attrId)
    local newValue = oldValue + value
    if newValue == 0 then
        newValue = nil
    end
    self.attrMap[attrId] = newValue
end

function AttrComponent:_MulFrom(other)
    local otherAttrList = other.attrMap or {}
    for k, v in pairs(otherAttrList) do
        local selfAttrV = self:_GetAttr(k)
        selfAttrV = math.floor(selfAttrV * (10000 + v) * 0.0001)
        self._SetAttr(k, selfAttrV)
    end
end

return AttrComponent
