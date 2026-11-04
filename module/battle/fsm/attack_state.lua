local Define = require "define.define"
local AttackState = class("AttackState")

function AttackState:Ctor(entity, fsm)
    self.target = nil
    self.entity = entity
    self.fsm = fsm
end

function AttackState:Enter(battle, skillId, target, performDis)
    self.target = target
    self.skillId = skillId
    self.performDis = performDis
    self.entity:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT):StopAtCurrentPosition(battle)
    if target then
        local selfPos = self.entity:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT):GetPosition()
        local targetPos = target:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT):GetPosition()
        local dis = ((selfPos.x - targetPos.x) ^ 2 + (selfPos.y - targetPos.y) ^ 2) ^ 0.5
        local dirX = (targetPos.x - selfPos.x) / dis
        local dirY = (targetPos.y - selfPos.y) / dis
        self.entity:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT):SetDirection(dirX, dirY)
    end
    self.entity:GetComponent(Define.COMPONENT_TYPE.SKILL_COMPONENT):PerformSkill(battle, skillId, target)
end

function AttackState:Leave(battle, ...)
    self.target = nil
    self.skillId = nil
    self.performDis = nil
end

function AttackState:Update(battle)
    local canInterrupt = self.entity:GetComponent(Define.COMPONENT_TYPE.SKILL_COMPONENT):CanInterrupt(battle)
    if not canInterrupt then
        return
    end
    self.entity:GetComponent(Define.COMPONENT_TYPE.SKILL_COMPONENT):InterruptSkill(true)
    self.fsm:ChangeState(battle, Define.FSM_STATE.SEARCH_TARGET_STATE)
end

return AttackState
