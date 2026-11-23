local Class = require "common.class"

---@class SkillComponent
---@field owner SceneUnit
---@field lastCast table|nil
local SkillComponent = Class("SkillComponent")

-- 同一个场景服务中的所有施法者共用序号。换图重建组件时继续取下一个号。
local lastCastId = 0

-- 每个宿主拥有自己的最近施法记录。开始施法时从宿主读取 UID。
function SkillComponent:Ctor(owner)
    self.owner = owner
    self.lastCast = nil
end

-- 场景完成准入检查后调用一次。每次新建快照，后续施法不会覆盖已返回的记录。
function SkillComponent:BeginCast(req, effectId, now)
assert(lastCastId < math.maxinteger, "cast ID exhausted")
    lastCastId = lastCastId + 1
    local cast = {
        castId = lastCastId,
        casterUid = self.owner.uid,
        skillId = req.skillId,
        skillLevel = req.skillLevel,
        effectId = effectId,
        targetUid = req.targetUid,
        startedAt = now,
    }
    self.lastCast = cast
    return cast
end


return SkillComponent