local Define = require "define.define"
local EntityBase = require "entity.entity_base"

local HeroEntity = class("HeroEntity", EntityBase)

function HeroEntity:Ctor(entityId, cfgId, avatar)
    EntityBase.Ctor(self, entityId)
    self.cfgId = cfgId
    self.avatar = avatar
end

-- 获取实体类型
function HeroEntity:GetEntityType()
    return Define.ENTITY_TYPE.HERO
end

-- 获取配置id
function HeroEntity:GetCfgId()
    return self.cfgId
end

-- 获取头像
function HeroEntity:GetAvatar()
    return self.avatar
end

-- 获取职业
function HeroEntity:GetCareer()
    return self.avatar.career or 1
end

-- 获取性别
function HeroEntity:GetSex()
    return self.avatar.sex or 1
end

-- 获取等级
function HeroEntity:GetLevel()
    return self.avatar.level or 1
end

function HeroEntity:_OnInit(battle)
    local attrComponent = self:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT)
    local skillComponent = self:GetComponent(Define.COMPONENT_TYPE.SKILL_COMPONENT)
    for k, v in pairs(self.avatar.attrMap) do
        attrComponent:SetAttrBySource(Define.ENTITY_ATTR_SOURCE.BASE, k, math.floor(v))
    end

    for _, v in pairs(self.avatar.activeSkill) do
        skillComponent:AddActiveSkill(v.skillId, self.avatar.animation, v.lv)
    end

    for _, v in pairs(self.avatar.passiveSkill) do
        skillComponent:AddPassiveSkill(battle, v.skillId, v.lv)
    end
end

--获取实体注册的所有类型
function HeroEntity:GetEntityAllTypes()
    return { Define.ENTITY_TYPE.ENTITY, Define.ENTITY_TYPE.HERO }
end

return HeroEntity
