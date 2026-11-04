local Define = require "define.define"
local Bomb = require "spawn_obj.bomb"
local HitAction = require "hit_action.hit_action"

local BombHitAction = class("BombHitAction", HitAction)
function BombHitAction:DoAction(config, battle, entity, skillEffectInfo)
    local moveComponent = entity:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT)
    local selfPos = moveComponent:GetPosition()
    local basePos = nil
    local target = battle:GetEntityById(skillEffectInfo.targetId)
    local targetId = 0
    if self.following then
        if self.toTarget == Define.BOMB_TARGET_TYPE.SELF then
            basePos = selfPos
        else
            if not target then
                basePos = skillEffectInfo.pos
            else
                local targetMoveComponent = target:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT)
                basePos = targetMoveComponent:GetPosition()
            end
        end
    else
        if self.toTarget == Define.BOMB_TARGET_TYPE.SELF then
            basePos = { x = selfPos.x, y = selfPos.y }
        else
            if not target then
                basePos = skillEffectInfo.pos
            else
                local targetMoveComponent = target:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT)
                local targetPos = targetMoveComponent:GetPosition()
                basePos = { x = targetPos.x, y = targetPos.y }
            end
        end
    end
    local bombObj = Bomb.new(battle, entity, basePos, skillEffectInfo, config)
    bombObj:SetTargetId(targetId)
    battle:AddSpawn(bombObj)
end

return BombHitAction
