local BaseComponent = require "component.base_component"
local Define = require "define.define"
local Buff = require "buff.buff"
local ConfigHelper = require "config.config_helper"
local SkillComponent = class("SkillComponent", BaseComponent)

function SkillComponent:Ctor()
    BaseComponent.Ctor(self)
    self.normalSkillId = 0
    self.activeSkills = {}
    self.activeSkillReq = {}
    self.passiveSkills = {}
    self.runningEffectMap = {}
    self.currentEffectIdx = 0
    self.endTime = 0
    self.nextNormalAttackTime = 0
    self.attackSpeed = 1
    self.attackInterval = 1
    self.currentSkillId = 0
end

function SkillComponent:_UpdateAttackSpeed()
    local attrComponent = self.owner:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT)
    local attackSpeed = attrComponent:GetAttr(Define.ENTITY_ATTR.ATTACK_SPEED)
    self.attackSpeed = attackSpeed
    if attackSpeed > 0 then
        self.attackInterval = 1000.0 // attackSpeed
    end
end

function SkillComponent:OnAttach(battle)
    self:_UpdateAttackSpeed()
end

function SkillComponent:Update(battle, dt)
    self:_UpdateAttackSpeed()
end

function SkillComponent:AddActiveSkill(skillId, battleanimation, level)
    local activeSkillCfg = Data.TBBattleActiveSkill[skillId]
    if not activeSkillCfg then
        return false
    end
    -- 角色所有动作的动画
    local animation = Data.TBBattleAnimation[battleanimation]
    if not animation then
        return false
    end
    -- 这个技能对应的动画
    local skillAnimation = animation.animations[activeSkillCfg.animation]
    local levelActionGroupId = level
    if levelActionGroupId > #activeSkillCfg.levelActionGroupId then
        levelActionGroupId = #activeSkillCfg.levelActionGroupId
    end

    -- 技能的行为组id
    local levelGroupId = activeSkillCfg.levelActionGroupId[level]
    local skillGroupCfg = Data.TBBattleActiveSkillActionGroup[levelGroupId]
    local activeSkillObj = {
        cd = 0,
        hitActionList = {},
        level = level,
        cfg = activeSkillCfg,
        priority = activeSkillCfg.priority,
        dur = skillAnimation.duration,
    }

    -- skillGroupCfg.actionList 为每个技能的所有效果列表（但是里面不包含每个效果的开始时间）
    -- 每个效果的开始时间在 skillAnimation.events[k].time
    -- 这里就是将每个效果的开始时间和效果的配置合并
    for k, v in ipairs(skillGroupCfg.actionList) do
        local event = skillAnimation.events[k]
        if not event then
            goto continue
        end
        local hitZone = skillGroupCfg.hitzoneList[v.hitzoneIdx]
        local hitActionObj = {
            idx = k,
            startTime = event.time,
            hitActionCfg = v,
            hitZone = hitZone,
        }
        table.insert(activeSkillObj.hitActionList, hitActionObj)
        ::continue::
    end
    self.activeSkills[skillId] = activeSkillObj
    if activeSkillCfg.normal then
        assert(self.normalSkillId == 0)
        self.normalSkillId = skillId
    end
    return true
end

function SkillComponent:AddPassiveSkill(battle, skillId, level)
    local passiveSkillCfg = Data.TBBattlePassiveSkill
    local cfg = passiveSkillCfg[skillId]
    assert(cfg, string.format("没有配置的被动技能 skillId:%s", skillId))
    local maxCfgLv = #cfg.levelBuffId
    local buffId = cfg.levelBuffId[level] or cfg.levelBuffId[maxCfgLv]
    local buffCfg = Data.TBBattleBuff[buffId]
    assert(buffCfg, string.format("没有配置的被动技能buff buffId:%s", buffId))
    Buff.InstallBuff(battle, buffCfg, self.owner)
end

function SkillComponent:PostUpdate(battle, _)
    if not self.runningEffectMap or not next(self.runningEffectMap) then
        return
    end
    local eTime = battle:GetExpireTime()
    local len = #self.runningEffectMap
    local idx = self.currentEffectIdx

    for i = idx, len do
        local skillEffect = self.runningEffectMap[i]
        if skillEffect.beginTime > eTime then
            break
        end
        local hitAction = skillEffect.actionCfg
        -- HitAction(hitAction, battle, self.owner, skillEffect)
        ConfigHelper.GetConfigClass(hitAction):DoAction(hitAction, battle, self.owner, skillEffect)
        self.currentEffectIdx = self.currentEffectIdx + 1
    end
    if self.currentEffectIdx > len then
        self.runningEffectMap = nil
    end
end

function SkillComponent:PerformSkill(battle, skillId, target)
    local eTime = battle:GetExpireTime()
    -- 当前正在释放的技能
    if self.normalSkillId == skillId and self.nextNormalAttackTime > eTime then
        return
    end

    local owner = self.owner
    local skill = self.activeSkills[skillId]
    local skillCfg = skill.cfg
    if not skill then
        return
    end
    local stateComponent = owner:GetComponent(Define.COMPONENT_TYPE.STATE_COMPONENT)
    -- 不能使用普通攻击
    if self.normalSkillId == skillId and not stateComponent:IsEnable(Define.ENTITY_ABILIT.NORMAL_ATTACK) then
        return
    end

    -- 不能释放技能
    if not stateComponent:IsEnable(Define.ENTITY_ABILIT.SKILL_ATTACK) then
        return
    end

    if skill.cd > eTime then
        return
    end

    local fightComponent = owner:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    -- 魔法不够
    if skillCfg.cost > fightComponent:GetMp() then
        return
    end

    if skillCfg.needTarget then
        if not target then
            return
        end
        local targetStateComponent = target:GetComponent(Define.COMPONENT_TYPE.STATE_COMPONENT)
        if not targetStateComponent:IsEnable(Define.ENTITY_ABILIT.BE_TARGET) then
            return
        end
    end

    if self.normalSkillId == skillId then
        self.nextNormalAttackTime = eTime + self.attackInterval
    end
    -- 重置当前释放的技能
    self:InterruptSkill(true)
    local lastCd = skillCfg.cd[#skillCfg.cd] or 1
    -- 该技能cd好的时间戳
    skill.cd = eTime + (skillCfg.cd[skill.level] or lastCd)
    fightComponent:CostMp(battle, skillCfg.cost)
    local param = { battle = battle, performer = self.owner, skillId = skillId, target = target }
    self.owner:FireEvent(Define.BATTLE_EVENT.ENTITY_BEFORE_PERFORM_SKILL_EVENT, param)
    if target then
        self.owner:FireEvent(Define.BATTLE_EVENT.ENTITY_BEFORE_BE_PERFORM_SKILL_EVENT, param)
    end
    self.currentSkillId = skillId
    self:_SpellSkill(battle, target, skillCfg, skill)
    self.owner:FireEvent(Define.BATTLE_EVENT.ENTITY_AFTER_PERFORM_SKILL_EVENT, param)
    if target then
        self.owner:FireEvent(Define.BATTLE_EVENT.ENTITY_AFTER_BE_PERFORM_SKILL_EVENT, param)
    end

    battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_PERFORM_SKILL_ACTION, {
        entityId = owner:GetId(),
        skillId = skillId,
        targetId = target and target:GetId() or nil,
    })
end

-- 计算出释放技能的效果顺序
function SkillComponent:_SpellSkill(battle, target, skillCfg, activeSkill)
    local pos = target and target:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT):GetPosition()
    local targetId = target and target:GetId()
    local eTime = battle:GetExpireTime()
    local owner = self.owner
    local state = skillCfg.normal and Define.ENTITY_STATE.NORMAL_SKILL_STATE or Define.ENTITY_STATE.SKILL_STATE
    self.owner:GetComponent(Define.COMPONENT_TYPE.STATE_COMPONENT):SetState(battle, state, activeSkill.dur)
    self.endTime = eTime + activeSkill.dur
    self.runningEffectMap = {}
    for i, v in pairs(activeSkill.hitActionList) do
        table.insert(self.runningEffectMap, {
            targetId = targetId,
            actionCfg = v.hitActionCfg,
            hitZone = v.hitZone,
            level = activeSkill.level,
            skillId = activeSkill.cfg.id,
            beginTime = eTime + v.startTime,
            hitActionIdx = i,
            pos = { x = pos.x, y = pos.y },
        })
    end
    self.currentEffectIdx = 1
    local param = { battle = battle, performer = owner, skillId = skillCfg.id, dur = activeSkill.dur }
    battle:FireEvent(Define.BATTLE_EVENT.ENTITY_SPELL_SKILL_EVENT, param)
end

-- 获取最佳释放的技能
function SkillComponent:CalcBestSkill(battle)
    local eTime = battle:GetExpireTime()
    local skillId = self.normalSkillId
    local lastWeight = self.activeSkills[skillId].priority
    for _, id in ipairs(self.activeSkillReq) do
        local activeSkill = self.activeSkills[id]
        if not activeSkill then
            goto continue
        end
        if id == self.normalSkillId then
            goto continue
        end
        if activeSkill.cd >= eTime then
            goto continue
        end
        if activeSkill.priority <= lastWeight then
            goto continue
        end
        skillId = id
        lastWeight = activeSkill.priority
        ::continue::
    end
    return skillId
end

-- 中断当前释放的技能
function SkillComponent:InterruptSkill()
    self.runningEffectMap = nil
    self.currentEffectIdx = 1
    self.currentSkillId = 0
    self.owner:GetComponent(Define.COMPONENT_TYPE.STATE_COMPONENT):ClearState(Define.ENTITY_STATE.SKILL_STATE)
    self.owner:GetComponent(Define.COMPONENT_TYPE.STATE_COMPONENT):ClearState(Define.ENTITY_STATE.NORMAL_SKILL_STATE)
end

function SkillComponent:IncreaseSkillPriority(skillId, priority)
    local skill = self.activeSkills[skillId]
    if not skill then
        return
    end
    skill.priority = priority
end

function SkillComponent:GetActiveSkill(skillId)
    return self.activeSkills[skillId]
end

function SkillComponent:GetSkillEndTime()
    return self.endTime
end

function SkillComponent:GetMaxDistance(battle)
    local fightComponent = self.owner:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    local eTime = battle:GetExpireTime()
    local maxDistance = 0
    local skillId = 0
    for k, v in pairs(self.activeSkills) do
        if v.cd > eTime then
            goto continue
        end
        local skillCfg = v.cfg
        if skillCfg.cost > fightComponent:GetMP() then
            goto continue
        end
        if skillCfg.performDis > maxDistance then
            maxDistance = skillCfg.performDis
            skillId = k
        end
        ::continue::
    end
    return skillId, maxDistance
end

function SkillComponent:GetBestActiveSkill(battle, excludeIds)
    local fightComponent = self.owner:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    local eTime = battle:GetExpireTime()
    local normalSkill = self.activeSkills[self.normalSkillId]
    assert(normalSkill, string.format("normalSkill 不能为空 skillId:%s", self.normalSkillId))
    local priority = normalSkill.cfg.priority
    local activeSkill = normalSkill
    local skillId = normalSkill.cfg.id
    for k, v in pairs(self.activeSkills) do
        if excludeIds and excludeIds[k] then
            goto continue
        end
        if v.cd >= eTime then
            goto continue
        end
        local skillCfg = v.cfg
        if skillCfg.cost > fightComponent:GetMp() then
            goto continue
        end
        if (not skillCfg.normal and not self.owner:GetComponent(Define.COMPONENT_TYPE.STATE_COMPONENT):IsEnable(Define.ENTITY_ABILIT.SKILL_ATTACK)) then
            goto continue
        end
        if skillCfg.priority > priority then
            priority = skillCfg.priority
            activeSkill = v
            skillId = k
        end
        ::continue::
    end
    return skillId, activeSkill.cfg.performDis
end

function SkillComponent:CanInterrupt(battle)
    if self.currentSkillId == 0 then
        return true
    end
    if self.normalSkillId == self.currentSkillId then
        return self.runningEffectMap == nil or not next(self.runningEffectMap)
    end
    return self.endTime <= battle:GetExpireTime()
end

function SkillComponent:Pack(package)
    package.activeSkills = {}
    for k, v in pairs(self.activeSkills) do
        table.insert(package.activeSkills, {
            id = k,
            level = v.level,
        })
    end
end

return SkillComponent
