local ConfigHelper = require "config.config_helper"
local Define = require "define.define"
local TraceButtle = class("TraceButtle")

function TraceButtle:Ctor(battle, performer, skillEffectInfo, buttleCfg)
    self.id = battle:GenerateEntityId()
    self.cfg = buttleCfg
    self.performer = performer
    self.skillEffectInfo = skillEffectInfo
    local moveComponent = performer:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT)
    local selfPos = moveComponent:GetPosition()
    self.curPos = { x = selfPos.x, y = selfPos.y }
    local targetId = self.skillEffectInfo.targetId
    local target = battle:GetEntityById(targetId)
    assert(target)
    local targetMoveComponent = target:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT)
    self.targetPos = targetMoveComponent:GetPosition()
end

function TraceButtle:GetId()
    return self.id
end

-- 返回值表示是否移除
function TraceButtle:Update(battle, dt)
    local targetId = self.skillEffectInfo.targetId
    local target = battle:GetEntityById(targetId)
    -- 目标已消失 移除子弹
    if not target then
        return true
    end
    local dis = (self.curPos.x - self.targetPos.x) ^ 2 + (self.curPos.y - self.targetPos.y) ^ 2
    local moveDis = self.cfg.speed * dt * 0.001
    -- 没有打到
    if moveDis < dis then
        self.curPos.x = self.curPos.x + moveDis * (self.targetPos.x - self.curPos.x) / dis
        self.curPos.y = self.curPos.y + moveDis * (self.targetPos.y - self.curPos.y) / dis
        return false
    end
    self:_OnShot(battle, target)
    return true
end

function TraceButtle:_OnShot(battle, target)
    local attacker = self.performer
    local hitActionGroupId = self.cfg.hitActionGroup
    local hitActionGroup = Data.TBSkillHitActionGroup[hitActionGroupId]
    local hitzoneList = hitActionGroup.hitzoneList
    for _, action in ipairs(hitActionGroup.actionList) do
        local hitzone = hitzoneList[action.hitzoneIdx]
        if not hitzone then
            return
        end
        if self.syncAction then
            self.syncAction.onHitFrame = battle.context:GetFrameCount()
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

function TraceButtle:OnEnterScene(battle)
    self.syncAction = {
        objId = self.id,
        basePos = { x = self.curPos.x, y = self.curPos.y },
        targetPos = { x = self.targetPos.x, y = self.targetPos.y },
        speed = self.cfg.speed,
        skillId = self.skillEffectInfo.skillId,
        hitActionIdx = self.skillEffectInfo.hitActionIdx,
        performerId = self.performer:GetId(),
        onHitFrame = 0 -- 真正命中的是否再去修改这个
    }
    battle:AddFrameAction(Define.BATTLE_ACTION.BATTLE_ADD_BUTTLE_ACTION, self.syncAction)
end

function TraceButtle:OnLeaveScene(battle)
    battle:AddFrameAction(Define.BATTLE_ACTION.BATTLE_REMOVE_BUTTLE_ACTION, { objId = self.id })
end

return TraceButtle
