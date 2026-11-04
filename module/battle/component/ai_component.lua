local Define = require "define.define"
local SearchStateHandler = require "fsm.search_target_state"
local MoveStateHandler = require "fsm.move_state"
local AttackStateHandler = require "fsm.attack_state"
local BaseComponent = require "component.base_component"
local AIComponent = class("AIComponent", BaseComponent)

function AIComponent:Ctor()
    self.target = nil
    self.currentState = nil
    self.normalAttackTime = 0
    self.stateHandlers = {}
end

function AIComponent:OnAttach(battle)
    local owner = self.owner
    self.stateHandlers[Define.FSM_STATE.SEARCH_TARGET_STATE] = SearchStateHandler.new(owner, self)
    self.stateHandlers[Define.FSM_STATE.MOVE_STATE] = MoveStateHandler.new(owner, self)
    self.stateHandlers[Define.FSM_STATE.ATTACK_STATE] = AttackStateHandler.new(owner, self)
    self.currentState = Define.FSM_STATE.SEARCH_TARGET_STATE
    local currentStateHandler = self.stateHandlers[self.currentState]
    assert(currentStateHandler, string.format("currentStateHandler 不能为空 state:%s", self.currentState))
    currentStateHandler:Enter(battle)
end

function AIComponent:ChangeState(battle, state, ...)
    local currentStateHandler = self.stateHandlers[self.currentState]
    currentStateHandler:Leave(battle, ...)
    self.currentState = state
    local newStateHandler = self.stateHandlers[state]
    assert(currentStateHandler, string.format("currentStateHandler 不能为空 state:%s", self.currentState))
    newStateHandler:Enter(battle, ...)
end

function AIComponent:PostUpdate(battle, _)
    local stateComponent = self.owner:GetComponent(Define.COMPONENT_TYPE.STATE_COMPONENT)

    -- 不能执行 ai 动作
    if not stateComponent:IsEnable(Define.ENTITY_ABILIT.AI) then
        return
    end
    local currentStateHandler = self.stateHandlers[self.currentState]
    assert(currentStateHandler, string.format("currentStateHandler 不能为空 state:%s", self.currentState))
    currentStateHandler:Update(battle)
end

return AIComponent
