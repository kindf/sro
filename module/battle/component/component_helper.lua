local StateComponent = require "component.state_component"
local FightComponent = require "component.fight_component"
local BuffComponent = require "component.buff_component"
local SkillComponent = require "component.skill_component"
local AttrComponent = require "component.attr_component"
local MoveComponent = require "component.move_component"
local AIComponent = require "component.ai_component"

local Define = require "define.define"
local ComponentHelper = {}
local componentCreaterMap = {}

local function RegisterComponentCteater(type, creater)
    componentCreaterMap[type] = creater
end

local function _CreateFunc(c)
    return function()
        return c.new()
    end
end

RegisterComponentCteater(Define.COMPONENT_TYPE.STATE_COMPONENT, _CreateFunc(StateComponent))
RegisterComponentCteater(Define.COMPONENT_TYPE.FIGHT_COMPONENT, _CreateFunc(FightComponent))
RegisterComponentCteater(Define.COMPONENT_TYPE.BUFF_COMPONENT, _CreateFunc(BuffComponent))
RegisterComponentCteater(Define.COMPONENT_TYPE.SKILL_COMPONENT, _CreateFunc(SkillComponent))
RegisterComponentCteater(Define.COMPONENT_TYPE.ATTR_COMPONENT, _CreateFunc(AttrComponent))
RegisterComponentCteater(Define.COMPONENT_TYPE.MOVE_COMPONENT, _CreateFunc(MoveComponent))
RegisterComponentCteater(Define.COMPONENT_TYPE.AI_COMPONENT, _CreateFunc(AIComponent))

function ComponentHelper.CreateComponent(ComponentType)
    assert(componentCreaterMap[ComponentType], string.format("没有这个组件 type:%s", ComponentType))
    return componentCreaterMap[ComponentType]()
end

return ComponentHelper
