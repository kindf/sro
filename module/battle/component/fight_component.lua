local BaseComponent = require "component.base_component"
local Define = require "define.define"
local FightComponent = class("FightComponent", BaseComponent)

function FightComponent:Ctor()
    BaseComponent.Ctor(self)
    self.hp = 0                                               -- 当前血量
    self.mp = 0                                               -- 当前魔法
    self.camp = 0                                             -- 阵营
    self.isDead = false                                       -- 是否死亡
    self.fightState = Define.ENTITY_BATTLE_STATE.NORMAL_STATE -- 战斗状态
    self.radius = 1                                           -- 半径
    self.maxHp = 0                                            -- 最大血量
    self.maxMp = 0                                            -- 最大魔法
end

function FightComponent:OnAttach()
    local AttrComponent = self.owner:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT)
    self.maxHp = AttrComponent:GetAttr(Define.ENTITY_ATTR.MAX_HP)
    self.maxMp = AttrComponent:GetAttr(Define.ENTITY_ATTR.MAX_MP)
    self.hp = self.maxHp
    self.mp = 0
    self.owner:RegisterEventHandler(Define.BATTLE_EVENT.ENTITY_AFTER_PERFORM_SKILL_EVENT, self, "_OnAfterPerformSkill")
end

function FightComponent:SetCamp(camp)
    self.camp = camp
end

function FightComponent:OnEnter()
end

function FightComponent:OnLeave()
    self.fightState = self.fightState | Define.ENTITY_BATTLE_STATE.REMOVED_STATE
end

function FightComponent:Removed()
    return self.fightState & Define.ENTITY_BATTLE_STATE.REMOVED_STATE ~= 0
end

function FightComponent:GetRadius()
    return self.radius
end

function FightComponent:GetCamp()
    return self.camp
end

function FightComponent:GetMp()
    return self.mp
end

-- 是否是自己
function FightComponent:_FilterSelf(target)
    return target == self.owner
end

-- 是否是友方
function FightComponent:_FilterFriends(target)
    local targetFightComponent = target:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    if not targetFightComponent then
        return false
    end
    if self.owner == target then
        return false
    end
    return targetFightComponent:GetCamp() == self:GetCamp()
end

-- 是否是敌方
function FightComponent:_FilterEnemies(target)
    local targetFightComponent = target:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    if not targetFightComponent then
        return false
    end
    if self.owner == target then
        return false
    end
    return targetFightComponent:GetCamp() ~= self:GetCamp()
end

-- 是否是其他实体
function FightComponent:_FilterOthers(target)
    return target ~= self.owner
end

function FightComponent:_FilterAll(target)
    local targetFightComponent = target:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    if not targetFightComponent then
        return false
    end
    return true
end

local filterFuncs = {
    [Define.ENTITY_RELATION_TYPE.SELF] = FightComponent._FilterSelf,
    [Define.ENTITY_RELATION_TYPE.FRIENDS] = FightComponent._FilterFriends,
    [Define.ENTITY_RELATION_TYPE.ENEMIES] = FightComponent._FilterEnemies,
    [Define.ENTITY_RELATION_TYPE.OTHERS] = FightComponent._FilterOthers,
    [Define.ENTITY_RELATION_TYPE.ALL] = FightComponent._FilterAll,
}

function FightComponent:IsRelaction(target, relationType)
    local filterFunc = filterFuncs[relationType]
    if not filterFunc then
        return false
    end
    return filterFunc(self, target)
end

function FightComponent:IsHit(_)
    return true
end

function FightComponent:DoDamage(battle, value)
    local stateComponent = self.owner:GetComponent(Define.COMPONENT_TYPE.STATE_COMPONENT)
    if not stateComponent:IsEnable(Define.ENTITY_ABILIT.BE_DAMAGE) then
        return 0, 0
    end
    local finalDamage = math.min(value, self.hp)
    self.hp = self.hp - finalDamage

    battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_UPDATE_HP_ACTION, {
        entityId = self.owner:GetId(),
        curHp = self.hp,
    })
    if self.hp <= 0 then
        self.fightState = self.fightState | Define.ENTITY_BATTLE_STATE.DEAD_STATE
        battle:FireEvent(Define.BATTLE_EVENT.ENTITY_DEAD_EVENT, {entityId = self.owner:GetId()})
    end
    return finalDamage
end

function FightComponent:DoHeal(battle, healValue)
    local stateComponent = self.owner:GetComponent(Define.COMPONENT_TYPE.STATE_COMPONENT)
    if not stateComponent:IsEnable(Define.ENTITY_ABILIT.BE_HEAL) then
        return 0
    end
    local oldHp = self.hp
    self.hp = math.min(self.hp + healValue, self.maxHp)
    battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_UPDATE_HP_ACTION, {
        entityId = self.owner:GetId(),
        curHp = self.hp,
    })
    return self.hp - oldHp
end

function FightComponent:Dead()
    return self.fightState & Define.ENTITY_BATTLE_STATE.DEAD_STATE ~= 0
end

function FightComponent:AddMp(battle, mp)
    local attrComponent = self.owner:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT)
    local maxMp = attrComponent:GetAttr(Define.ENTITY_ATTR.MAX_MP)
    self.mp = math.min(self.mp + mp, maxMp)
    battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_UPDATE_MP_ACTION, {
        entityId = self.owner:GetId(),
        curMp = self.mp,
    })
end

function FightComponent:CostMp(battle, mp)
    self.mp = math.max(self.mp - mp, 0)
    battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_UPDATE_MP_ACTION, {
        entityId = self.owner:GetId(),
        curMp = self.mp,
    })
end

function FightComponent:_OnAfterPerformSkill(_, param)
    local attrComponent = self.owner:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT)
    local attackSpeed = attrComponent:GetAttr(Define.ENTITY_ATTR.ATTACK_SPEED)
    if attackSpeed <= 0 then
        return
    end
    local skillId = param.skillId
    local skillCfg = Data.TBBattleActiveSkill[skillId]
    if skillCfg.performAddAnger <= 0 then
        return
    end
    local MaxAdd = Data.TBBattleParam.attackAddAngerMin
    local delta = math.floor(skillCfg.performAddAnger * attackSpeed)
    delta = math.max(MaxAdd, delta)
    self:AddMp(param.battle, delta)
end

function FightComponent:Update(battle, _)
    local attrComponent = self.owner:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT)
    local newHp = attrComponent:GetAttr(Define.ENTITY_ATTR.MAX_HP)
    local newMp = attrComponent:GetAttr(Define.ENTITY_ATTR.MAX_MP)
    if self.maxHp ~= newHp then
        self.maxHp = newHp
        battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_UPDATE_MAX_HP_ACTION, {
            entityId = self.owner:GetId(),
            maxHp = self.maxHp,
        })
    end
    if self.maxMp ~= newMp then
        self.maxMp = newMp
        battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_UPDATE_MAX_MP_ACTION, {
            entityId = self.owner:GetId(),
            maxMp = self.maxMp,
        })
    end
end

function FightComponent:Pack(package)
    package.hp = self.hp
    package.mp = self.mp
    package.maxHp = self.owner:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT):GetAttr(Define.ENTITY_ATTR.MAX_HP)
    package.maxMp = self.owner:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT):GetAttr(Define.ENTITY_ATTR.MAX_MP)
end

return FightComponent
