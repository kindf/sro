local ConfigHelper = require "config.config_helper"
local Define = require "define.define"
local Bomb = class("Bomb")

function Bomb:Ctor(battle, performer, pos, skillEffectInfo, bombCfg)
    self.id = battle:GenerateEntityId()
    self.cfg = bombCfg
    self.basePos = pos
    self.performer = performer
    self.skillEffectInfo = skillEffectInfo
    local effectCfg = Data.TBSkillEffectFrameEvent[self.cfg.effect]
    self.timeLine = effectCfg.events
    local hitActionGroupId = self.cfg.hitActionGroup
    self.hitActionGroup = Data.TBSkillHitActionGroup[hitActionGroupId]
    self.curHitActionIdx = 1
    self.startTime = battle:GetExpireTime()
end

function Bomb:GetId()
    return self.id
end

function Bomb:Update(battle, _)
    local eTime = battle:GetExpireTime()
    local totalEventNum = #self.timeLine
    local curIdx = self.curHitActionIdx
    local hitActionList = self.hitActionGroup.actionList
    local hitZoneList = self.hitActionGroup.hitzoneList
    for i = curIdx, totalEventNum do
        repeat
            local actionTime = self.timeLine[i]
            if eTime < self.startTime + actionTime.time then
                break
            end
            self.curHitActionIdx = self.curHitActionIdx + 1
            local action = hitActionList[i]
            if not action then
                return true
            end
            local hitZone = hitZoneList[action.hitzoneIdx]
            if not hitZone then
                return true
            end
            local targetIdList = ConfigHelper.GetConfigClass(hitZone):SearchEntity(hitZone, battle, self.basePos,
                self.performer, Define.ENTITY_TYPE.ENTITY, self.targetId)
            for _, v in ipairs(targetIdList) do
                local e = battle:GetEntityById(v)
                if e then
                    ConfigHelper.GetConfigClass(action):_OnDoAction(action, battle, self.performer, e,
                        self.skillEffectInfo)
                end
            end
        until true
    end
    return self.curHitActionIdx > #self.timeLine
end

function Bomb:SetHitActionIdx(idx)
    self.hitActionIdx = idx
end

function Bomb:SetTargetId(targetId)
    self.targetId = targetId
end

function Bomb:OnEnterScene(battle)
    battle:AddFrameAction(Define.BATTLE_ACTION.BATTLE_ADD_BOMB_ACTION, {
        objId = self.id,
        basePos = { x = self.basePos.x, y = self.basePos.y },
        targetId = self.target,
        skillId = self.skillEffectInfo.skillId,
        hitActionIdx = self.skillEffectInfo.hitActionIdx,
        performerId = self.performer:GetId()
    })
end

function Bomb:OnLeaveScene(battle)
end

return Bomb
