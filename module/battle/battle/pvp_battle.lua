local Define = require "define.define"
local BattleBase = require "battle.battle_base"
local HeroEntity = require "entity.hero_entity"

local PvpBattle = class("PvpBattle", BattleBase)
 
function PvpBattle:Ctor(frame, battleId)
    BattleBase.Ctor(self, frame, battleId)
    self.campNum = {}
    self.attackerHeroList = nil
    self.defenderHeroList = nil
    self.attackerCamp = nil
    self.defenderCamp = nil
end

function PvpBattle:SetAttackerHeroList(heroList)
    self.attackerHeroList = heroList
end

function PvpBattle:SetDefenderHeroList(heroList)
    self.defenderHeroList = heroList
end

function PvpBattle:SetCamp(attackerCamp, defenderCamp)
    self.attackerCamp = attackerCamp
    self.defenderCamp = defenderCamp
    self.campNum[attackerCamp] = 0
    self.campNum[defenderCamp] = 0
end

function PvpBattle:_OnStart()
    local tbbp = Data.TBBattleParam
    local f = function(heroList, camp, dirX, dirY, memberType, formation, posList)
        for _, v in ipairs(heroList) do
            local entityId = self:GenerateEntityId()
            local entity = HeroEntity.new(entityId, v.id, v)
            entity:Init(self)
            self:AddEntity(entity)
            local pos = posList[v.posNum]
            entity:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT):SetPosition(pos.x, pos.y)
            entity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT):SetCamp(camp)
            entity:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT):SetDirection(dirX, dirY)
            local campNum = self.campNum[camp]
            self.campNum[camp] = campNum + 1
            table.insert(formation, {
                lv = v.lv,
                cfgId = v.id,
                posNum = v.posNum,
                entityId = entityId,
                activeSkill = v.activeSkill,
                memberType = memberType
            })
        end
    end

    local attackerFormation = {}
    local defenderFormation = {}
    local attackerBornPosList = tbbp.pveAttackerBornPosList
    local defenderBornPosList = tbbp.pveDefenderBornPosList
    f(self.attackerHeroList, self.attackerCamp, 1, 0, 1, attackerFormation, attackerBornPosList)
    f(self.defenderHeroList, self.defenderCamp, -1, 0, 2, defenderFormation, defenderBornPosList)
    self:AddFrameAction(Define.BATTLE_ACTION.BATTLE_INIT_FORMATION_ACTION, {
        attackerFormation = attackerFormation,
        defenderFormation = defenderFormation
    })
end

function PvpBattle:_CheckEnd()
    local tbbp = Data.TBBattleParam
    local camp1 = self.campNum[self.attackerCamp]
    local camp2 = self.campNum[self.defenderCamp]
    if camp1 == 0 or camp2 == 0 then
        return true
    end
    if self:GetExpireTime() > tbbp.timeout * 1000 then
        return true
    end
    return false
end

function PvpBattle:IsWin()
    local tbbp = Data.TBBattleParam
    local eTime = self:GetExpireTime()
    if eTime >= tbbp.timeout * 1000 then
        return false
    end
    if (self.campNum[self.attackerCamp] or 0) == 0 then
        return false
    end
    if (self.campNum[self.defenderCamp] or 0) == 0 then
        return true
    end
    return false
end

function PvpBattle:_OnEntityRemove(entity)
    local fightComponent = entity:GetComponent(Define.COMPONENT_TYPE.FIGHT_COMPONENT)
    local campNum = self.campNum[fightComponent:GetCamp()]
    assert(campNum)
    campNum = campNum - 1
    self.campNum[fightComponent:GetCamp()] = campNum
end

return PvpBattle
