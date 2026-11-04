local Define = require "define.define"
local RectangleHitZone = class("RectangleHitZone")

local function filter(selfEntity, targetEntity, targetRelation, center, direction, hw, hh)
    local selfFightComponent = selfEntity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    if not selfFightComponent:IsRelaction(targetEntity, targetRelation) then
        return false
    end
    local targetBodyRadius = targetEntity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT):GetRadius()
    local targetMoveComponent = targetEntity:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT)
    local target2CenterX = targetMoveComponent:GetPosition().x - center.x
    local target2CenterY = targetMoveComponent:GetPosition().y - center.y
    if (target2CenterX * target2CenterX + target2CenterY * target2CenterY) - targetBodyRadius * targetBodyRadius <= 0.01 then
        return true
    end

    local target2CenterVecterX = target2CenterX * direction.y - target2CenterY * direction.x
    local target2CenterVecterY = target2CenterX * direction.x + target2CenterY * direction.y
    local absx = math.abs(target2CenterVecterX)
    local absy = math.abs(target2CenterVecterY)
    if absx > hw + targetBodyRadius or absy > hh + targetBodyRadius then
        return false
    end

    if (absx - hw <= 0.01 or absy - hh <= 0.01 or ((absx - hw) ^ 2 + (absy - hh) ^ 2) - targetBodyRadius ^ 2 <= 0.01) then
        return true
    end
    return false
end

function RectangleHitZone:SearchEntity(config, battle, pos, entity, entityType, priorityEntityId)
    local entities = battle:GetEntityByType(entityType)
    local moveComponent = entity:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT)
    local direction = moveComponent:GetDirection()
    local centerX = direction.x * config.xoffset + pos.x - direction.y * config.yoffset
    local centerY = direction.y * config.xoffset + pos.y + direction.x * config.yoffset
    local hw, hh = config.width * 0.5, config.height * 0.5
    local ret = {}
    local hitCnt = config.hitcnt or 1
    hitCnt = math.max(hitCnt, 1)
    priorityEntityId = priorityEntityId or 0
    local e = entities[priorityEntityId]
    local cnt = 0
    if e and filter(entity, e, config.target, { x = centerX, y = centerY }, direction, hw, hh) then
        table.insert(ret, priorityEntityId)
        cnt = cnt + 1
    end
    for k, v in pairs(entities) do
        if cnt >= hitCnt then
            break
        end
        if k ~= priorityEntityId and filter(entity, v, config.target, { x = centerX, y = centerY }, direction, hw, hh) then
            table.insert(ret, v)
            cnt = cnt + 1
        end
    end
    return ret
end

return RectangleHitZone
