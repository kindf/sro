local Define = require "define.define"
local CircleHitZone = class("CircleHitZone")
local function filter(selfEntity, targetEntity, targetRelation, center, radius)
    local selfFightComponent = selfEntity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    if not selfFightComponent or not selfFightComponent:IsRelaction(targetEntity, targetRelation) then
        return false
    end
    local targetPos = targetEntity:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT):GetPosition()
    local targetBodyRadius = targetEntity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT):GetRadius()
    local distance = math.sqrt((targetPos.x - center.x) * (targetPos.x - center.x) +
        (targetPos.y - center.y) * (targetPos.y - center.y))
    if distance - math.sqrt(targetBodyRadius * targetBodyRadius) <= 0.01 then
        return true
    end
    if distance - math.sqrt(radius * radius) > 0.01 then
        return false
    end
    return true
end

function CircleHitZone:SearchEntity(config, battle, pos, entity, entityType, priorityEntityId)
    local ret = {}
    local entities = battle:GetEntityByType(entityType)
    local moveComponent = entity:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT)
    local direction = moveComponent:GetDirection()
    local basePos = pos
    local centerX = direction.x * config.xoffset + basePos.x - direction.y * config.yoffset
    local centerY = direction.y * config.xoffset + basePos.y + direction.x * config.yoffset
    local hitCnt = config.hitCnt or 1
    hitCnt = hitCnt <= 0 and 1 or hitCnt
    local cnt = 0
    priorityEntityId = priorityEntityId or 0
    local priorityEntity = entities[priorityEntityId]
    if priorityEntity and filter(entity, priorityEntity, config.target, basePos, config.radius) then
        table.insert(ret, priorityEntityId)
        cnt = cnt + 1
    end

    for k, v in pairs(entities) do
        if cnt >= hitCnt then
            break
        end
        if k ~= priorityEntityId and filter(entity, v, config.target, { x = centerX, y = centerY }, config.radius) then
            table.insert(ret, k)
            cnt = cnt + 1
        end
    end
    return ret
end

return CircleHitZone
