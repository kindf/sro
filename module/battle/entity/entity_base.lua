local ComponentHelper = require "component.component_helper"
local Define = require "define.define"
local EventHandler = require "util.event_handler"

local EntityBase = class("EntityBase")

function EntityBase:Ctor(entityId)
    self.id = entityId
    self.mapCom = {}
    self.eventHandler = EventHandler.new()
end

-- 获取实体id
function EntityBase:GetId()
    return self.id
end

-- 获取实体类型
function EntityBase:GetEntityType()
    return Define.ENTITY_TYPE.ENTITY
end

-- 获取职业
function EntityBase:GetCareer()
    return 0
end

-- 获取性别
function EntityBase:GetSex()
    return 0
end

-- 实体进入战斗
function EntityBase:OnEnter()
    local fightComponent = self:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    if not fightComponent then
        fightComponent:OnEnter()
    end
    self:FireEvent(Define.BATTLE_EVENT.ENTITY_AFTER_BORN_EVENT, self)
end

-- 实体离开战斗
function EntityBase:OnLeave()
    local fightComponent = self:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    if not fightComponent then
        fightComponent:OnEnter()
    end
end

-- 获取组件
function EntityBase:GetComponent(type)
    return self.mapCom[type]
end

-- 获取需要注册的组件
function EntityBase:GetRegisterComponents()
    local entityType = self:GetEntityType()
    return Define.ENTITY_REGISTER_COMPONENT[entityType]
end

-- 初始化
function EntityBase:Init(battle)
    for _, v in ipairs(self:GetRegisterComponents()) do
        local component = ComponentHelper.CreateComponent(v)
        self:RegisterComponent(v, component)
    end

    self:_OnInit(battle)

    for _, v in pairs(self.mapCom) do
        v:OnAttach(battle)
    end
end

function EntityBase:_OnInit(_)
end

-- 获取需要更新的组件(按顺序）
function EntityBase:GetUpdateComponentOrder()
    local entityType = self:GetEntityType()
    return Define.ENTITY_COMPONENT_UPDATE_ORDER[entityType]
end

-- 更新
function EntityBase:Update(battle, deltaTime)
    for _, v in ipairs(self:GetUpdateComponentOrder()) do
        local component = self:GetComponent(v)
        assert(component)
        component:Update(battle, deltaTime)
    end
end

-- 获取需要后更新的组件(按顺序）
function EntityBase:GetPostUpdateComponentOrder()
    local entityType = self:GetEntityType()
    return Define.ENTITY_COMPONENT_POST_UPDATE_ORDER[entityType]
end

-- 后更新
function EntityBase:PostUpdate(battle, deltaTime)
    for _, v in ipairs(self:GetPostUpdateComponentOrder()) do
        local component = self:GetComponent(v)
        assert(component)
        component:PostUpdate(battle, deltaTime)
    end
end

-- 注册组件
function EntityBase:RegisterComponent(type, component)
    assert(self.mapCom[type] == nil, "重复注册组件")
    self.mapCom[type] = component
    component:SetOwner(self)
end

-- 注册事件
function EntityBase:FireEvent(eventType, param)
    self.eventHandler:FireEvent(eventType, param)
end

function EntityBase:RegisterEventHandler(eventType, target, handler, priority)
    self.eventHandler:RegisterEventHandler(eventType, target, handler, priority)
end

-- 获取实体注册的所有类型
function EntityBase:GetEntityAllTypes()
    return {Define.ENTITY_TYPE.ENTITY}
end

function EntityBase:Destroy()
    for _, v in pairs(self.mapCom) do
        v:OnDetach()
    end
    self:_OnDestroy()
end

function EntityBase:_OnDestroy()
end

function EntityBase:Pack()
    local ret = {}
    ret.entityId = self.id
    ret.entityType = self:GetEntityType()
    ret.cfgId = self.cfgId
    for _, v in pairs(self.mapCom) do
        v:Pack(ret)
    end
    return ret
end

return EntityBase
