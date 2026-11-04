local ConfigHelper = require "config.config_helper"
local Define = require "define.define"
local Buttle = class("Buttle")

function Buttle:Ctor(battle, performer, skillEffectInfo, buttleCfg)
    self.cfg = buttleCfg
    self.performer = performer
    self.skillEffectInfo = skillEffectInfo
    self.id = battle:GenerateEntityId()
    local moveComponent = performer:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT)
    local selfPos = moveComponent:GetPosition()
    self.pos = { x = selfPos.x, y = selfPos.y }
    self.curPos = { x = selfPos.x, y = selfPos.y }
    local dir = moveComponent:GetDirection()
    self.targetPos = {
        x = buttleCfg.range * dir.x + selfPos.x,
        y = buttleCfg.range * dir.y + selfPos.y
    }
    self.movedLen = 0
end

function Buttle:GetId()
    return self.id
end

local function clamp(x, minv, maxv)
    if x < minv then return minv end
    if x > maxv then return maxv end
    return x
end

-- 半径为r的圆和线段的交点
local function SegmentCircleIntersect(x1, y1, x2, y2, cx, cy, r)
    local abx = x2 - x1
    local aby = y2 - y1
    local acx = cx - x1
    local acy = cy - y1
    local ab2 = abx * abx + aby * aby
    if ab2 == 0 then
        local dx = acx
        local dy = acy
        local dist = dx * dx + dy * dy
        return dist <= r * r
    end

    local t = (abx * acx + aby * acy) / ab2
    t = clamp(t, 0, 1)
    local px = x1 + t * abx
    local py = y1 + t * aby
    local dx = px - cx
    local dy = py - cy
    local dist = dx * dx + dy * dy
    return dist <= r * r
end

-- 返回值：是否移除子弹
function Buttle:Update(battle, dt)
    local speed = self.cfg.speed
    local times = math.max(speed * 0.001 * dt // 20, 1)
    local spDt = dt / times
    local fightComponent = self.performer:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    for _ = 1, times do
        local moveDis = speed * spDt * 0.001
        self.movedLen = self.movedLen + moveDis
        local pathLen = self.cfg.range
        local movePercent = self.movedLen / pathLen
        local nx = self.pos.x + (self.targetPos.x - self.pos.x) * movePercent
        local ny = self.pos.y + (self.targetPos.y - self.pos.y) * movePercent
        if self.movedLen >= pathLen then
            return true
        end
        local allEntities = battle:GetAllEntity()
        for k, v in pairs(allEntities) do
            repeat
                local targetFightComponent = v:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
                if targetFightComponent:GetCamp() == fightComponent:GetCamp() then
                    break
                end
                if (not v:GetComponent(Define.COMPONENT_TYPE.STATE_COMPONENT):IsEnable(Define.ENTITY_ABILIT.BE_TARGET)) or targetFightComponent:Dead() then
                    break
                end
                local targetMoveComponent = v:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT)
                local vr = targetFightComponent:GetRadius()
                local targetPos = targetMoveComponent:GetPosition()
                local ret = SegmentCircleIntersect(self.curPos.x, self.curPos.y, nx, ny, targetPos.x, targetPos.y,
                    vr + self.cfg.radius)
                if not ret then
                    break
                end
                if self.syncAction then
                    self.syncAction.targetId = k
                    self.syncAction.frame = battle.context:GetFrameCount()
                end
                self:_OnShot(battle, v)
                return true
            until true
        end
        self.curPos.x = nx
        self.curPos.y = ny
    end
    return false
end

function Buttle:_OnShot(battle, target)
    local attacker = self.performer
    local hitActionGroupId = self.cfg.hitActionGroup
    local hitActionGroup = Data.TBSkillHitActionGroup[hitActionGroupId]
    local hitzoneList = hitActionGroup.hitzoneList
    for _, action in ipairs(hitActionGroup.actionList) do
        local hitzone = hitzoneList[action.hitzoneIdx]
        if not hitzone then
            return
        end
        local eList = ConfigHelper.GetConfigClass(hitzone):SearchEntity(hitzone, battle, self.curPos, attacker,
            Define.ENTITY_TYPE.ENTITY, target:GetId())
        for _, v in ipairs(eList) do
            local e = battle:GetEntityById(v)
            if e then
                ConfigHelper.GetConfigClass(action):_OnDoAction(action, battle, attacker, e, self.skillEffectInfo)
            end
        end
    end
end

function Buttle:OnEnterScene(battle)
    self.syncAction = {
        objId = self.id,
        basePos = { x = self.pos.x, y = self.pos.y },
        targetPos = { x = self.targetPos.x, y = self.targetPos.y },
        speed = self.cfg.speed,
        skillId = self.skillEffectInfo.skillId,
        hitActionIdx = self.skillEffectInfo.hitActionIdx,
        performerId = self.performer:GetId(),
        --TODO: debug
        dir = self.performer:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT):GetDirection()
    }
    battle:AddFrameAction(Define.BATTLE_ACTION.BATTLE_ADD_BUTTLE_ACTION, self.syncAction)
end

function Buttle:OnLeaveScene(battle)
    battle:AddFrameAction(Define.BATTLE_ACTION.BATTLE_REMOVE_BUTTLE_ACTION, { objId = self.id })
end

return Buttle
