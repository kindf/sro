local Class = require "common.class"
local FightGroupComponent = require "scene.fight_group_component"

---@class SkillComponent
---@field owner SceneUnit
---@field lastCast table|nil
local SkillComponent = Class("SkillComponent")

-- 同一个场景服务中的所有施法者共用序号。换图重建组件时继续取下一个号。
local lastCastId = 0

local RANGE_UNIT = 0
local TARGET_ALL = 0
local TARGET_ENEMY = 4
local TARGET_DEAD_FRIEND = 5

-- 每个宿主拥有自己的最近施法记录。开始施法时从宿主读取 UID。
function SkillComponent:Ctor(owner)
    self.owner = owner
    self.lastCast = nil
end

-- 只处理锁定活单位的敌方和友方主目标；其它技能沿用原有选取方式。
function SkillComponent:CanSelectPrimary(skill, target)
    if skill.SkillTargetRangeType ~= RANGE_UNIT then
        return not target.dead
    end

    local casterGroup = self.owner:GetComponent(FightGroupComponent)
    local targetGroup = target:GetComponent(FightGroupComponent)
    if not casterGroup or not targetGroup then
        return false
    end

    local targetType = skill.TargetType
    if targetType == TARGET_ALL then
        return true
    end
    local requiresDead = targetType == TARGET_DEAD_FRIEND
    if target.dead ~= requiresDead then
        return false
    end
    local enemy = FightGroupComponent.IsEnemy(casterGroup, targetGroup)
    if targetType == TARGET_ENEMY then
        return enemy
    end

    return not enemy
end

-- 场景完成准入检查后调用一次。每次新建快照，后续施法不会覆盖已返回的记录。
function SkillComponent:BeginCast(req, effectId, now, targetUid, point)
assert(lastCastId < math.maxinteger, "cast ID exhausted")
    lastCastId = lastCastId + 1
    local cast = {
        castId = lastCastId,
        casterUid = self.owner.uid,
        skillId = req.skillId,
        skillLevel = req.skillLevel,
        effectId = effectId,
        startedAt = now,
        targetUid = targetUid,
        castPoint = {x = point.x, y = point.y, z = point.z}
    }
    self.lastCast = cast
    return cast
end


return SkillComponent
