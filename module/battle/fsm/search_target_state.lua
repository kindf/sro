local Define = require "define.define"
local SearchTargetHandler = {}

local function ForEachEntity(battle, entity, targetRelation, callback)
    local fightComponent = entity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    local entities = battle:GetAllEntity()
    for _, v in pairs(entities) do
        local stateComponent = v:GetComponent(Define.COMPONENT_TYPE.STATE_COMPONENT)
        if stateComponent:IsEnable(Define.ENTITY_ABILIT.BE_DAMAGE)
            and fightComponent:IsRelaction(v, targetRelation) then
            callback(v)
        end
    end
end

SearchTargetHandler[Define.SKILL_APPOINT_TYPE.MOST_ATTACK] = function(battle, entity, targetRelation)
    local fightComponent = entity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    local maxAttack = 0
    local target = nil
    ForEachEntity(battle, entity, targetRelation, function(v)
        local attrComponent = v:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT)
        local att = attrComponent:GetAttr(Define.ENTITY_ATTR.ATT)
        if att > maxAttack and fightComponent:IsRelaction(v, targetRelation) then
            maxAttack = att
            target = v
        end
    end)
    return target
end

SearchTargetHandler[Define.SKILL_APPOINT_TYPE.LEAST_ATTACK] = function(battle, entity, targetRelation)
    local fightComponent = entity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    local minAttack = math.maxinteger
    local target = nil
    ForEachEntity(battle, entity, targetRelation, function(v)
        local attrComponent = v:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT)
        local att = attrComponent:GetAttr(Define.ENTITY_ATTR.ATT)
        if att < minAttack and fightComponent:IsRelaction(v, targetRelation) then
            minAttack = att
            target = v
        end
    end)
    return target
end

SearchTargetHandler[Define.SKILL_APPOINT_TYPE.LEAST_HP] = function(battle, entity, targetRelation)
    local fightComponent = entity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    local minHp = math.maxinteger
    local target = nil
    ForEachEntity(battle, entity, targetRelation, function(v)
        local attrComponent = v:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT)
        local hp = attrComponent:GetAttr(Define.ENTITY_ATTR.MAX_HP)
        if hp < minHp and fightComponent:IsRelaction(v, targetRelation) then
            minHp = hp
            target = v
        end
    end)
    return target
end

SearchTargetHandler[Define.SKILL_APPOINT_TYPE.MOST_HP] = function(battle, entity, targetRelation)
    local fightComponent = entity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    local maxHp = 0
    local target = nil
    ForEachEntity(battle, entity, targetRelation, function(v)
        local attrComponent = v:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT)
        local hp = attrComponent:GetAttr(Define.ENTITY_ATTR.MAX_HP)
        if hp > maxHp and fightComponent:IsRelaction(v, targetRelation) then
            maxHp = hp
            target = v
        end
    end)
    return target
end

SearchTargetHandler[Define.SKILL_APPOINT_TYPE.LEAST_DEF] = function(battle, entity, targetRelation)
    local fightComponent = entity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    local minDef = math.maxinteger
    local target = nil
    ForEachEntity(battle, entity, targetRelation, function(v)
        local attrComponent = v:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT)
        local def = attrComponent:GetAttr(Define.ENTITY_ATTR.DEF)
        if def < minDef and fightComponent:IsRelaction(v, targetRelation) then
            minDef = def
            target = v
        end
    end)
    return target
end

SearchTargetHandler[Define.SKILL_APPOINT_TYPE.MOST_DEF] = function(battle, entity, targetRelation)
    local fightComponent = entity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    local maxDef = 0
    local target = nil
    ForEachEntity(battle, entity, targetRelation, function(v)
        local attrComponent = v:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT)
        local def = attrComponent:GetAttr(Define.ENTITY_ATTR.DEF)
        if def > maxDef and fightComponent:IsRelaction(v, targetRelation) then
            maxDef = def
            target = v
        end
    end)
    return target
end

SearchTargetHandler[Define.SKILL_APPOINT_TYPE.FARTHEST] = function(battle, entity, targetRelation)
    local fightComponent = entity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    local selfMoveComponent = entity:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT)
    local selfPos = selfMoveComponent:GetPosition()
    local farthestDis = 0
    local target = nil
    ForEachEntity(battle, entity, targetRelation, function(v)
        local moveComponent = v:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT)
        local pos = moveComponent:GetPosition()
        local dis = ((selfPos.x - pos.x) ^ 2 + (selfPos.y - pos.y) ^ 2) ^ 0.5
        if dis > farthestDis and fightComponent:IsRelaction(v, targetRelation) then
            farthestDis = dis
            target = v
        end
    end)
    return target
end

SearchTargetHandler[Define.SKILL_APPOINT_TYPE.CLOSEST] = function(battle, entity, targetRelation)
    local fightComponent = entity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    local selfMoveComponent = entity:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT)
    local selfPos = selfMoveComponent:GetPosition()
    local closestDis = math.maxinteger
    local target = nil
    ForEachEntity(battle, entity, targetRelation, function(v)
        local moveComponent = v:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT)
        local pos = moveComponent:GetPosition()
        local dis = ((selfPos.x - pos.x) ^ 2 + (selfPos.y - pos.y) ^ 2) ^ 0.5
        if dis < closestDis and fightComponent:IsRelaction(v, targetRelation) then
            closestDis = dis
            target = v
        end
    end)
    return target
end

local function GetPerfectSkill(battle, entity)
    local target, skillId, performDis
    local excludeIds = {}
    local skillComponent = entity:GetComponent(Define.COMPONENT_TYPE.SKILL_COMPONENT)
    repeat
        skillId, performDis = skillComponent:GetBestActiveSkill(battle, excludeIds)
        local skillCfg = Data.TBBattleActiveSkill[skillId]
        if not skillCfg.needTarget then
            return skillId, performDis, nil
        end
        target = SearchTargetHandler[skillCfg.appointType](battle, entity, skillCfg.targetRelation)
        if not target then
            excludeIds[skillId] = true
            if skillCfg.normal then
                return nil, nil, nil
            end
        end
    until target
    return skillId, performDis, target
end

local SearchTargetState = class("SearchTargetState")

function SearchTargetState:Ctor(entity, fsm)
    self.fsm = fsm
    self.entity = entity
end

function SearchTargetState:Enter(battle)
end

function SearchTargetState:Leave(battle)
end

function SearchTargetState:Update(battle)
    local skillId, performDis, target = GetPerfectSkill(battle, self.entity)
    if not skillId then
        return
    end
    if not target then
        self.fsm:ChangeState(battle, Define.FSM_STATE.ATTACK_STATE, skillId, nil, performDis)
        return
    end

    local selfPos = self.entity:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT):GetPosition()
    local targetPos = target:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT):GetPosition()
    local dis = ((selfPos.x - targetPos.x) ^ 2 + (selfPos.y - targetPos.y) ^ 2) ^ 0.5
    if dis - performDis <= 0.01 then
        self.fsm:ChangeState(battle, Define.FSM_STATE.ATTACK_STATE, skillId, target, performDis)
    else
        self.fsm:ChangeState(battle, Define.FSM_STATE.MOVE_STATE, skillId, target, performDis)
    end
end

return SearchTargetState
