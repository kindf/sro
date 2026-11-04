local Define = require "define.define"
local Buttle = require "spawn_obj.buttle"
local TraceButtle = require "spawn_obj.trace_buttle"
local HitAction = require "hit_action.hit_action"

local ButtleHitAction = class("ButtleHitAction", HitAction)
function ButtleHitAction:DoAction(config, battle, entity, skillEffect)
    if not self.trace then
        local buttleObj = Buttle.new(battle, entity, skillEffect, config)
        battle:AddSpawn(buttleObj)
        return
    end
    if skillEffect.targetId == 0 then
        return
    end
    local target = battle:GetEntityById(skillEffect.targetId)
    if not target then
        return
    end
    if target:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT):Dead() then
        return
    end
    local buttleObj = TraceButtle.new(battle, entity, skillEffect, config)
    battle:AddSpawn(buttleObj)
end

function ButtleHitAction:_OnDoAction()
end

return ButtleHitAction
