local Class = require "common.class"
local ConfigRepository = require "common.config_repository"

local FightGroupComponent = Class("FightGroupComponent")

local ROLE = 0
local FIRST_PVP_GROUP = 6
local MOB_GROUP_OFFSET = 10000

local columns = {
    [0] = "Role",
    [1] = "Monster",
    [2] = "Neutral",
    [3] = "Enemy",
    [4] = "SpecialNpc",
    [5] = "SpecialNpc2",
}

-- 场景玩家从角色组出生；怪物从实体模板还原原版运行时组号。
function FightGroupComponent:Ctor(owner, template)
    local group = ROLE
    if template then
        group = template.DefaultGroup
        if template.IsDynamicGroup then
            group = FIRST_PVP_GROUP + group - 1
        end
    end
    if group == ROLE and not owner:IsPlayer() then
        group = MOB_GROUP_OFFSET
    end
    self.group = group
end

-- 矩阵按 attacker 行、sufferer 列读取
function FightGroupComponent.IsEnemy(sufferer, attacker)
    local row = attacker.group % MOB_GROUP_OFFSET
    local column = sufferer.group % MOB_GROUP_OFFSET
    if row >= FIRST_PVP_GROUP and column >= FIRST_PVP_GROUP then
        return row ~= column
    end
    local lastPveGroup = FIRST_PVP_GROUP - 1
    local relations = ConfigRepository.Get("tbfightgrouptable")
    local relationRow = relations[math.min(row, lastPveGroup)]
    local field = columns[math.min(column, lastPveGroup)]
    return relationRow[field] == "o"
end

return FightGroupComponent