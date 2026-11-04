local Define = require "define.define"
local MoveState = class("MoveState")

function MoveState:Ctor(entity, fsm)
    self.fsm = fsm
    self.entity = entity
end

function MoveState:Enter(battle, skillId, target, performDis)
    self.targetPos = nil
    self.skillId = skillId
    self.target = target
    self.performDis = performDis
end

function MoveState:Leave(battle, ...)
    self.targetPos = nil
    self.target = nil
end

function MoveState:Update(battle)
    local target = self.target
    if not target then
        return
    end
    local targetStateComponent = target:GetComponent(Define.COMPONENT_TYPE.STATE_COMPONENT)
    local targetMoveComponent = target:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT)
    local selfMoveComponent = self.entity:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT)
    if not targetStateComponent:IsEnable(Define.ENTITY_ABILIT.BE_DAMAGE) then
        selfMoveComponent:StopAtCurrentPosition(battle, true)
        self.fsm:ChangeState(battle, Define.FSM_STATE.SEARCH_TARGET_STATE)
        return
    end
    local selfPos = selfMoveComponent:GetPosition()
    local targetPos = target:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT):GetPosition()
    local dis = (((selfPos.x - targetPos.x) ^ 2 + (selfPos.y - targetPos.y) ^ 2)) ^ 0.5
    local selfFightComponent = self.entity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    local targetFightComponent = target:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    local s = selfFightComponent:GetRadius() + targetFightComponent:GetRadius()
    if dis - s <= 0.01 or (dis - s) - self.performDis <= 0.01 then
        selfMoveComponent:StopAtCurrentPosition(battle, true)
        self.fsm:ChangeState(battle, Define.FSM_STATE.ATTACK_STATE, self.skillId, target, self.performDis)
        return
    end
    if self.targetPos and not targetMoveComponent:IsMoving()
        and math.abs(self.targetPos.x - targetPos.x) <= 0.01
        and math.abs(self.targetPos.y - targetPos.y) <= 0.01 then
        return
    end
    -- 目标位置改变 重新计算
    self.targetPos = self.targetPos or {}
    self.targetPos.x = targetPos.x
    self.targetPos.y = targetPos.y
    local dirX = (self.targetPos.x - selfPos.x) / dis
    local dirY = (self.targetPos.y - selfPos.y) / dis
    selfMoveComponent:SetDirection(dirX, dirY)
    -- 新的目标点位置
    local newTargetPosX = targetPos.x - dirX * (s + self.performDis)
    local newTargetPosY = targetPos.y - dirY * (s + self.performDis)
    if selfMoveComponent:IsMoving() then
        selfMoveComponent:StopAtCurrentPosition(battle)
    end
    selfMoveComponent:MoveToPos(battle, newTargetPosX, newTargetPosY)
end

return MoveState
