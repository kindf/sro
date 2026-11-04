local BaseComponent = require "component.base_component"
local Define = require "define.define"
local StateComponent = class("StateComponent", BaseComponent)

function StateComponent:Ctor()
    BaseComponent.Ctor(self)
    self.abilities = ~0
    self.states = {}
    self.minEndTime = math.maxinteger
end

function StateComponent:IsEnable(ability)
    return self.abilities & (1 << (ability - 1)) ~= 0
end

function StateComponent:_CalcExpireTime(battle, dur)
    local eTime = battle:GetExpireTime()
    return eTime + dur
end

function StateComponent:SetState(battle, stateId, dur)
    dur = dur or math.maxinteger
    if dur <= 0 then
        return
    end
    local state = self.states[stateId]
    if not state then
        local cfg = Data.TBBattleState[stateId]
        assert(cfg, string.format("没有配置的状态 stateId:%s", stateId))
        local abilities = 0
        for i = 0, Define.ENTITY_ABILIT.MAX - 1 do
            if cfg.abilitys[i + 1] then
                abilities = abilities | (1 << i)
            end
        end
        state = { abilities = abilities, id = stateId }
        self.states[stateId] = state
        self.abilities = self.abilities & state.abilities
    end
    state.endTime = self:_CalcExpireTime(battle, dur)
    if state.endTime < self.minEndTime then
        self.minEndTime = state.endTime
    end
end

function StateComponent:HasState(stateId)
    return self.states[stateId]
end

function StateComponent:SetStateForever(battle, stateId)
    self:SetState(battle, stateId, math.maxinteger)
end

function StateComponent:ClearState(stateId)
    if not self.states[stateId] then
        return
    end
    self.states[stateId] = nil
    self:BuildAbilities()
end

function StateComponent:BuildAbilities(_)
    self.minEndTime = math.maxinteger
    self.abilities = ~0
    for _, state in pairs(self.states) do
        if state.endTime < self.minEndTime then
            self.minEndTime = state.endTime
        end
        self.abilities = self.abilities & state.abilities
    end
end

function StateComponent:Update(battle, _)
    local eTime = battle:GetExpireTime()
    if eTime < self.minEndTime then
        return
    end
    local remove = {}
    for _, state in pairs(self.states) do
        if eTime >= state.endTime then
            remove[state.id] = true
        end
    end
    for id in pairs(remove) do
        self.states[id] = nil
    end
    self:BuildAbilities(battle)
end

return StateComponent
