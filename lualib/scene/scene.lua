local Class = require "common.class"
local SceneUnit = require "scene.scene_unit"
local Logger = require "common.logger"
local MonsterUnit = require "lualib.scene.monster_unit"
local ConfigRepository = require "common.config_repository"
local DropUnit = require("lualib.scene.drop_unit")
local skynet = require "skynet"
local MapLayerParser = require "lualib.scene.map_layer_parser"
local SkillConfig = require "common.skill_config"
local AttributeComponent = require "scene.attribute_component"
local SkillComponent = require "scene.skill_component"
local FightGroupComponent = require "scene.fight_group_component"
local SkillRange = require "scene.skill_range"

-- 场景尚未同步职业模型，先使用基础跑速
local NOVICE_PRESENT_ID = 10

local MAX_SPEED       = 6.0   -- 占位，后面从属性表取
local SPEED_TOLERANCE = 2.0   -- 允许 2 倍速度
local TOKEN_MAX       = 2.0   -- 最多攒 2 秒
local TOKEN_REGEN     = 1.0   -- 每秒回 1 秒
local MAX_DT          = 0.5   -- 单次最多补 500ms
local GRID_SIZE = 32       -- 32 米一格
local AOI_RADIUS = 1       -- 3x3
local DEFAULT_MAX_X = 10000 -- 默认地图尺寸
local DEFAULT_MIN_X = -10000-- 默认地图尺寸
local DEFAULT_MAX_Z = 10000-- 默认地图尺寸
local DEFAULT_MIN_Z = -10000-- 默认地图尺寸

local MONSTER_UID_BASE = 1000000 -- 怪物uid偏移
local DROP_UID_BASE = 2000000 -- 掉落物id偏移

local HEIGHT_LEGAL_DIFF = 0.4

local SKILL_RANGE       = 10.0
local SKILL_COOLDOWN    = 0.5
local SKILL_DAMAGE      = 100
local SKILL_OK          = 0
local SKILL_NO_TARGET   = 1
local SKILL_SELF        = 2
local SKILL_OUT_RANGE   = 3
local SKILL_COOLDOWNING = 4
local SKILL_TARGET_DEAD = 5
local SKILL_NOT_SELF    = 6
local SKILL_CASTER_DEAD = 7
local SKILL_NO_COST = 8
local SKILL_INVALID = 9

-- 技能范围类型
local RANGE_UNIT = 0 -- 指定目标类型
local RANGE_GROUND = 2 -- 地面范围类型

local TARGET_ENEMY = 4
local SHAPE_CIRCLE = 1

local ATTR_MAP = {
    [25] = "atk",  -- 基础素质攻击
    [27] = "atk",  -- 武器攻击
    [312] = "atk", -- 扩展武器攻击
    [30] = "def",  -- 本课接入的基础素质防御
}

local function IsEnemy(a, b)
    return (a:IsMonster() and b:IsPlayer()) or (a:IsPlayer() and b:IsMonster())
end

-- 射程和地面圆心均使用 XZ 平面；Y 留在快照供后续空间检查
local function HorizontalDistance(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.z - b.z)^2)
end

-- 显式点地没有主目标。按现有配置半径取圆内敌人，未接入的形状留给打击课
local function SelectGroundTargets(scene, caster, point, skill, effect)
    local targets = {}
    if not skill.IsAoe or skill.TargetType ~= TARGET_ENEMY or effect.EffectShape ~= SHAPE_CIRCLE then
        return targets
    end

    local radius = effect.EffectRange and effect.EffectRange[1]
    if not radius or radius <= 0 then
        return targets
    end

    local casterGroup = caster:GetComponent(FightGroupComponent)
    for _, candidate in pairs(scene.units) do
        if candidate ~= caster and not candidate.dead and HorizontalDistance(point, candidate) <= radius then
            local group = candidate:GetComponent(FightGroupComponent)
            if group and FightGroupComponent.IsEnemy(group, casterGroup) then
                table.insert(targets, candidate)
            end
        end
    end
    return targets
end

---@class Scene
---@field sceneId number
---@field units table<integer, SceneUnit>
---@field grids table<integer, table<integer, boolean>>
---@field startPost table
---@field startFace number
---@field minX number
---@field minZ number
---@field spawns table
---@field monsterSeq number
---@field dropSeq number
---@field heightLayers table
local Scene = Class("Scene")

function Scene:Ctor(cfg)
    self.sceneId = cfg.ID
    self.units = {}
    self.grids = {}

    self.startPos = cfg.StartPos and cfg.StartPos[1] or {0, 0, 0}
    self.startFace = math.floor(cfg.StartFace or 0)

    local size = cfg.MapSize and cfg.MapSize[1] or 0
    local offset = cfg.MapOffset and cfg.MapOffset[1] or {0, 0}

    if size > 0 then
        self.minX, self.maxX = offset[1], offset[1] + size
        self.minZ, self.maxZ = offset[2], offset[2] + size
    else
        self.minX, self.maxX = DEFAULT_MIN_X, DEFAULT_MAX_X
        self.minZ, self.maxZ = DEFAULT_MIN_Z, DEFAULT_MAX_Z
    end

    self.spawns = {}
    self.monsterSeq = 0
    self.dropSeq = 0

    self.heightLayers = {}
end

function Scene:LoadGrid(grid)
    self.grid = grid or {
        cell = 1.0,
        minX = self.minX, maxX = self.maxX,
        minZ = self.minZ, maxZ = self.maxZ,
        blocked = {},
    }
end

function Scene:GridKey(gx, gz)
    return gx.."_"..gz
end

---@param unit SceneUnit
function Scene:AddToGrid(unit)
    local gx = math.floor(unit.x / GRID_SIZE)
    local gz = math.floor(unit.z / GRID_SIZE)
    unit.gx, unit.gz = gx, gz

    local key = self:GridKey(gx, gz)
    local set = self.grids[key] or {}
    set[unit.uid] = true
    self.grids[key] = set
end

---@param unit SceneUnit
function Scene:RemoveFromGrid(unit)
    local key = self:GridKey(unit.gx, unit.gz)
    local set = self.grids[key]
    if set then
        set[unit.uid] = nil
        if next(set) == nil then
            self.grids[key] = nil
        end
    end
end

function Scene:GetNeighborSet(gx, gz)
    local result = {}
    for i = gx - AOI_RADIUS, gx + AOI_RADIUS do
        for j = gz - AOI_RADIUS, gz + AOI_RADIUS do
            local key = self:GridKey(i, j)
            local set = self.grids[key]
            if set then
                for uid in pairs(set) do
                    result[uid] = true
                end
            end
        end
    end
    return result
end

function Scene:Enter(uid, x, y, z, attrs)
    if not x then
        x, y, z = self.startPos[1], self.startPos[2], self.startPos[3]
    end
    local unit = SceneUnit.new()
    unit:AttachComponent(AttributeComponent, 10, 0)
    unit:AttachComponent(FightGroupComponent)
    unit:AttachComponent(SkillComponent)

    unit.uid = uid
    unit.x = x
    unit.y = self:GetHeight(x, z) or y
    unit.z = z
    unit.face = self.startFace or 0
    unit.lastMoveAt = skynet.now() / 100
    unit.token = TOKEN_MAX
    unit.dead = false
    unit.speed = ConfigRepository.Get("tbpresenttable")[NOVICE_PRESENT_ID].RunSpeed
    if attrs then
        self:ApplyBaseAttr(unit, attrs)
    end
    self.units[uid] = unit

    self:AddToGrid(unit)
    local neighbors = self:GetNeighborSet(unit.gx, unit.gz)
    neighbors[uid] = nil
    local others = {}
    for id, u in pairs(neighbors) do
        table.insert(others, self.units[id]:Pack())
    end

    return unit:Pack(), others
end

function Scene:Leave(uid)
    local unit = self.units[uid]
    if not unit then
        return nil, {}
    end

    local neighbors = self:GetNeighborSet(unit.gx, unit.gz)
    neighbors[uid] = nil

    
    self:RemoveFromGrid(unit)
    self.units[uid] = nil

    local others = {}
    for id, u in pairs(neighbors) do
        table.insert(others, self.units[id]:Pack())
    end

    return unit and unit:Pack(), others
end

local function _Finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

---@param unit SceneUnit
local function _ForcedBack(unit)
    return {
        dx = unit.x, dy = unit.y, dz = unit.z,
        time = 0, forced = true,
        receivers = {}, enters = {}, leaves = {},
    }
end

function Scene:Move(uid, moveContent)
    local unit = self.units[uid]
    if not unit then
        Logger.Warning("[Scene]Move: uid:%s not found in scene", tostring(uid))
        return
    end

    if unit.dead then
        return _ForcedBack(unit)
    end
    
    local dx, dy, dz, time = moveContent.dx, moveContent.dy, moveContent.dz, moveContent.time
    if not _Finite(dx) or not _Finite(dy) or not _Finite(dz) or not _Finite(time) then
        return _ForcedBack(unit)
    end

    if dx < self.minX or dx > self.maxX or dz < self.minZ or dz > self.maxZ then
        return _ForcedBack(unit)
    end

    time = math.max(0, math.min(2, time))

    local now = skynet.now() / 100
    local dt = now - unit.lastMoveAt
    if dt < 0 then dt = 0 end
    if dt > MAX_DT then dt = MAX_DT end

    local availableToken = math.min(TOKEN_MAX, unit.token + dt * TOKEN_REGEN)
    local dist = math.sqrt((dx - unit.x)^2 + (dz - unit.z)^2)
    local cost = dist / (MAX_SPEED * SPEED_TOLERANCE)
    if cost > availableToken then
        unit.token = 0
        unit.lastMoveAt = now
        return _ForcedBack(unit)
    end
    local canWalk, h = self:CanWalk(unit.x, unit.z, dx, dz)
    if not canWalk then
        return _ForcedBack(unit)
    end

    local oldGx, oldGz = unit.gx, unit.gz
    local newGx, newGz = math.floor(dx / GRID_SIZE), math.floor(dz / GRID_SIZE)
    local oldSet = self:GetNeighborSet(oldGx, oldGz)
    local newSet = self:GetNeighborSet(newGx, newGz)
    oldSet[unit.uid] = nil
    newSet[unit.uid] = nil

    local enters, leaves, receivers = {}, {}, {}
    for id in pairs(newSet) do
        if not oldSet[id] then
            table.insert(enters, self.units[id]:Pack())
        else
            table.insert(receivers, id)
        end
    end
    for id in pairs(oldSet) do
        if not newSet[id] then
            table.insert(leaves, id)
        end
    end

    local common = moveContent.common
    unit.x, unit.y, unit.z = dx, h, dz
    unit.lastMoveAt = now
    unit.token = availableToken - cost
    unit.face = common & 0xFFFF
    unit.moving = ((common >> 30) & 1) == 1
    self:RemoveFromGrid(unit)
    self:AddToGrid(unit)

    return {
        dx = dx,
        dy = h,
        dz = dz,
        time = time,
        forced = false,
        receivers = receivers,
        enters = enters,
        leaves = leaves,
    }
end

function Scene:GetUnit(uid)
    return self.units[uid]
end

-- 合并同一施法的击杀奖励，每件掉落保留自己的可见玩家。
local function MergeReward(a, b)
    if not b then return a end
    if not a then
        return b
    end

    a.baseExp = a.baseExp + b.baseExp
    a.jobExp = a.jobExp + b.jobExp
    a.totalBaseExp = b.totalBaseExp
    a.totalJobExp = b.totalJobExp
    a.level = b.level

    for _, d in ipairs(b.drops or {}) do
        a.drops[#a.drops + 1] = d
    end
    return a
end

-- 对本次受击者取实时防御。技能和怪物回退攻击可分别传入自己的伤害下限。
function Scene:CalculateHitDamage(target, rawDamage, minimum)
    local defense = target:GetComponent(AttributeComponent).def
    return math.max(minimum, math.floor(rawDamage - defense))
end

local function ApplySkillHits(target, damagePerHit, hitCount)
    local totalDamage = 0
    for _ = 1, hitCount do
        if target.hp <= 0 then
            break
        end

        target.hp = math.max(0, target.hp - damagePerHit)
        totalDamage = totalDamage + damagePerHit
    end
    return totalDamage
end

local function BuildCastResult(cast, primary, hits, buffs, reward)
    local first = hits[1]
    return {
        code = SKILL_OK,
        castId = cast.castId,
        cast = cast,
        targetUid = cast.targetUid,
        damage = first and first.damage or 0,
        targetHp = primary and primary.hp or 0,
        maxHp = primary and primary.maxHp or 0,
        hits = hits,
        dead = first and first.dead or false,
        reward = reward,
        buffs = buffs,
    }
end


function Scene:CastSkill(uid, req, now)
    local unit = self.units[uid]

    local failed = {
        targetUid = req.targetUid,
        damage = 0,
        targetHp = 0,
        maxHp = 0,
        receivers = {},
    }

    local skills = unit and unit:GetComponent(SkillComponent)
    if not skills or not unit:GetComponent(AttributeComponent) then
        failed.code = SKILL_NOT_SELF
        return failed
    end

    if unit.dead then
        failed.code = SKILL_CASTER_DEAD
        return failed
    end

    local skill = ConfigRepository.Get("tbskilltable")[req.skillId]
    local effectId = SkillConfig.GetEffectId(skill, req.skillLevel)
    local effect = effectId and ConfigRepository.Get("tbskilleffecttable")[effectId]
    if not effect then
        failed.code = SKILL_INVALID
        return failed
    end

    local reported = req.castPoint
    local ground = skill.SkillTargetRangeType == RANGE_GROUND and reported ~= nil
    local primary, targets
    if ground then
        failed.targetUid = 0
    else
        targets = self:SelectSkillTargets(uid, skill, effect, req.targetUid)
        if not targets then
            failed.code = SKILL_NO_TARGET
            return failed
        end
        primary = targets[1]
    end
    if reported ~= nil and (not _Finite(reported.x) or not _Finite(reported.y) or not _Finite(reported.z)) then
        failed.code = SKILL_OUT_RANGE
        return failed
    end

    local point = ground and reported or primary
    local lockedTarget = skill.SkillTargetRangeType == RANGE_UNIT and primary or nil
    local requestPoint = lockedTarget and reported or point
    if not SkillRange.Contains(unit, requestPoint, lockedTarget, effect) then
        failed.code = SKILL_OUT_RANGE
        return failed
    end

    -- 技能冷却检查
    local cooldown = effect.PVECoolTime or 0
    local last = unit.skillCooldown[req.skillId]
    if last and now - last < cooldown then
        failed.code = SKILL_COOLDOWNING
        return failed
    end

    -- 技能组冷却检查
    local groupId = effect.PVEGroupCoolTimeType or 0
    local nowMs = math.floor(now * 1000 + 0.5)
    local readyAtMs = unit.skillGroupReadyAtMs[groupId]
    if readyAtMs and nowMs < readyAtMs then
        failed.code = SKILL_COOLDOWNING
        return failed
    end

    -- SP 消耗
    local costType = effect.SkillCost and effect.SkillCost[1]
    local costValue = effect.SkillCost and effect.SkillCost[2] or 0
    if costType == 7 and unit.sp < costValue then
        failed.code = SKILL_NO_COST
        return failed
    end

    if ground then
        targets = SelectGroundTargets(self, unit, point, skill, effect)
    end
    local cast = skills:BeginCast(req, effectId, now, primary and primary.uid or 0, point)
    if costType == 7 then
        unit.sp = unit.sp - costValue
    end

    unit.skillCooldown[req.skillId] = now
    local groupDurationMs = math.floor((effect.PVEGroupCoolTime or 0) * 1000 + 0.5)
    if groupDurationMs > 0 then
        unit.skillGroupReadyAtMs[groupId] = nowMs + groupDurationMs
    end

    if #targets == 0 or (primary and primary.dead) then
        return BuildCastResult(cast, primary, {}, {})
    end

    local ratio = (effect.PVEDamageRadio and effect.PVEDamageRadio[1] or 10000) / 10000
    local static = effect.PVEStaticDam and effect.PVEStaticDam[1] or 0

    local hits = {}
    local rewardTotal = nil

    local attack = unit:GetComponent(AttributeComponent).atk
    for _, target in ipairs(targets) do
        local perHit = self:CalculateHitDamage(target, attack * ratio + static, ratio > 0 and 1 or 0)
        local hitCount = effect.AttackCount and effect.AttackCount[1] or 1
        local totalDamage = ApplySkillHits(target, perHit, hitCount)

        if target:IsMonster() then
            target:AddHatred(uid, totalDamage, now)
        end

        local dead = false
        if target.hp <= 0 and not target.dead then
            target.dead = true
            dead = true
        end

        local set = self:GetNeighborSet(target.gx, target.gz)
        local receivers, deadReceivers = {}, {}
        for id in pairs(set) do
            if id ~= uid then
                table.insert(receivers, id)
            end
            if dead then
                table.insert(deadReceivers, id)
            end
        end

        table.insert(hits, {
            castId = cast.castId,
            uid = target.uid,
            damage = totalDamage,
            hp = target.hp,
            maxHp = target.maxHp,
            receivers = receivers,
            dead = dead,
            deadReceivers = deadReceivers,
        })

        if dead and target:IsMonster() and unit:IsPlayer() then
            local r = self:GiveReward(unit, target)
            rewardTotal = MergeReward(rewardTotal, r)
        end
    end

    local buffs = {}

    for _, entry in ipairs(effect.CreateBuff or {}) do
        local buffId, rate = entry[1], entry[2] or 0
        local hit = rate >= 10000 or math.random(10000) <= rate
        if hit then
            local buff = self:ApplyBuff(uid, buffId, now)
            if buff then
                buffs[#buffs + 1] = buff
            end
        end
    end

    return BuildCastResult(cast, primary, hits, buffs, rewardTotal)
end

function Scene:GiveReward(player, monster)
    local cfg = ConfigRepository.Get("tbentitytable")[monster.entityId]
    if not cfg then
        return nil
    end

    local reward = {
        baseExp = cfg.BaseExp or 0,
        jobExp = cfg.JobExp or 0,
        totalBaseExp = 0,
        totalJobExp = 0,
        level = player.level,
        drops = {},
    }

    player.baseExp = player.baseExp + reward.baseExp
    player.jobExp = player.jobExp + reward.jobExp
    reward.totalBaseExp = player.baseExp
    reward.totalJobExp = player.jobExp

    local receivers = {}
    for id in pairs(self:GetNeighborSet(monster.gx, monster.gz)) do
        if self.units[id]:IsPlayer() then
            table.insert(receivers, id)
        end
    end

    -- Award：awardId -> pack -> item
    for _, awardId in ipairs(cfg.Award or {}) do
        local items = self:RollAward(awardId)
        for _, item in ipairs(items) do
            local drop = self:DropItem(item.itemId, item.count, monster.x, monster.z)
            table.insert(reward.drops, {unit = drop:Pack(), receivers = receivers})
        end
    end

    -- DropDoodad：直接 {itemId, count}
    for _, d in ipairs(cfg.DropDoodad or {}) do
        local drop = self:DropItem(d[1], d[2] or 1, monster.x, monster.z)
        table.insert(reward.drops, {unit = drop:Pack(), receivers = receivers})
    end

    return reward
end

function Scene:AddUnit(unit)
    self.units[unit.uid] = unit
    self:AddToGrid(unit)
end

function Scene:AddMonster(entityId, x, z)
    local cfg = ConfigRepository.Get("tbentitytable")[entityId]
    if not cfg then
        Logger.Error("[Scene]AddMonster: unknown entityId:%s", entityId)
        return nil
    end

    self.monsterSeq = self.monsterSeq + 1
    local unit = MonsterUnit.new(entityId, x, z)
    unit.y = self:GetHeight(x, z) or self.startPos[2]
    unit.lastMoveAt = skynet.now() / 100
    unit.token = TOKEN_MAX
    unit.uid = MONSTER_UID_BASE + self.monsterSeq
    unit.hp = cfg.BaseHP
    unit.maxHp = cfg.BaseHP
    unit.speed = cfg.MoveSpeed
    unit.singingTargetRadius = SkillRange.MonsterRadius(cfg.PresentID)
    unit.sight = cfg.Sight
    unit.aiType = cfg.AI[1]
    local attack = cfg.BaseATK > 0 and cfg.BaseATK or 10
    unit:AttachComponent(AttributeComponent, attack, cfg.BaseDEF)
    unit:AttachComponent(FightGroupComponent, cfg)
    unit:AttachComponent(SkillComponent)
    unit.skillIds = cfg.UnitSkillID or {}

    self:AddUnit(unit)
    return unit
end

function Scene:InitSpawns(defs)
    for i, def in ipairs(defs) do
        self.spawns[i] = {
            def = def,
            uid = nil,
            respawnAt = nil,
        }
        self:SpawnPoint(i)
    end
end

function Scene:SpawnPoint(index)
    local sp = self.spawns[index]
    if not sp then
        return nil
    end

    local unit = self:AddMonster(sp.def.entityId, sp.def.x, sp.def.z)
    if unit then
        sp.uid = unit.uid
        sp.respawnAt = nil
    end
    return unit
end

function Scene:Update(now)
    local events = {}
    self:UpdateAI(now, events)
    self:UpdateSpawns(now, events)
    self:UpdateBuffs(now, events)
    return events
end

function Scene:UpdateAI(now, events)
    for _, unit in pairs(self.units) do
        if not unit.dead then
            unit:UpdateAI(self, now, events)
        end
    end
    return events
end

---@param monster MonsterUnit
function Scene:FindNearestPlayer(monster)
    local best, bestDist
    for _, u in pairs(self.units) do
        if u:IsPlayer() and not u.dead then
            local d = math.sqrt((u.x - monster.x)^2 + (u.z - monster.z)^2)
            if d <= monster.sight and (not best or d < bestDist) then
                best = u
                bestDist = d
            end
        end
    end

    return best
end

function Scene:RemoveUnit(unit)
    if not unit then
        return
    end
    self:RemoveFromGrid(unit)
    self.units[unit.uid] = nil
end

function Scene:UpdateSpawns(now, events)
    for index, sp in ipairs(self.spawns) do
        local unit = self.units[sp.uid]

        if unit and unit.dead then
            if not sp.respawnAt then
                sp.respawnAt = now + sp.def.respawn
            end

            if now >= sp.respawnAt then
                local set = self:GetNeighborSet(unit.gx, unit.gz)
                local receivers = {}
                for uid in pairs(set) do
                    if uid ~= unit.uid then
                        table.insert(receivers, uid)
                    end
                end
                local oldUid = unit.uid
                self:RemoveUnit(unit)
                table.insert(events, {
                    kind = "leave",
                    uid = oldUid,
                    receivers = receivers,
                })

                local newUnit = self:SpawnPoint(index)
                if newUnit then
                    local newSet = self:GetNeighborSet(newUnit.gx, newUnit.gz)
                    local enterReceivers = {}
                    for uid in pairs(newSet) do
                        if uid ~= newUnit.uid then
                            table.insert(enterReceivers, uid)
                        end
                    end

                    table.insert(events, {
                        kind = "enter",
                        unit = newUnit:Pack(),
                        receivers = enterReceivers,
                    })
                end
            end
        end
    end
end

function Scene:DropItem(itemId, count, x, z)
    self.dropSeq = self.dropSeq + 1
    local unit = DropUnit.new(itemId, count, x, z)
    unit.uid = DROP_UID_BASE + self.dropSeq
    self:AddUnit(unit)
    return unit
end

-- 校验归属场景和距离。预检只返回物品信息，正式拾取会重新校验并移除掉落。
function Scene:Pickup(uid, targetUid, preview)
    local player = self.units[uid]
    local drop = self.units[targetUid]

    if not player or not drop or not drop.IsDrop or not drop:IsDrop() then
        return {code = 1} -- 不存在
    end

    local dist = math.sqrt((player.x - drop.x)^2 + (player.z - drop.z)^2)
    if dist > 2.0 then
        return {code = 2} -- 太远
    end

    if preview then
        return {code = 0, itemId = drop.itemId, count = drop.count}
    end

    local set = self:GetNeighborSet(drop.gx, drop.gz)
    local receivers = {}
    for id in pairs(set) do
        if id ~= drop.uid then
            table.insert(receivers, id)
        end
    end

    local itemId, count = drop.itemId, drop.count
    self:RemoveUnit(drop)

    return {
        code = 0,
        itemId = itemId,
        count = count,
        receivers = receivers,
    }
end

function Scene:DropItemAt(uid, itemId, count)
    local player = self.units[uid]
    if not player then
        return nil
    end

    local drop = self:DropItem(itemId, count, player.x, player.z)
    local set = self:GetNeighborSet(drop.gx, drop.gz)
    local receivers = {}
    for id in pairs(set) do
        table.insert(receivers, id)
    end
    return {unit = drop:Pack(), receivers = receivers}
end

function Scene:RollAward(awardId)
    local award = ConfigRepository.Get("tbawardtable")[awardId]
    local AwardPackTable = ConfigRepository.Get("tbawardpacktable")
    if not award then
        return {}
    end

    local result = {}

    for i, packId in ipairs(award.PackIds or {}) do
        local rate = award.PackRates and award.PackRates[i] or 0
        if rate > 0 and (rate >= 1 or math.random() < rate) then
            local pack = AwardPackTable[packId]
            local content = pack and pack.GroupContent and pack.GroupContent[1]
            if content then
                local itemId = content[1]
                local count = 1

                -- NumberInfo = {min, max}，今天先取 max 或 1
                if pack.NumberInfo and pack.NumberInfo[2] and pack.NumberInfo[2] > 0 then
                    count = pack.NumberInfo[2]
                end

                result[#result + 1] = {
                    itemId = itemId,
                    count = count,
                }
            end
        end
    end

    return result 
end

function Scene:ApplyBuff(uid, buffId, now)
    local unit = self.units[uid]
    local def = ConfigRepository.Get("tbbufftable")[buffId]
    if not unit or not unit:GetComponent(AttributeComponent) or not def then
        return nil
    end

    local duration = 3600
    if def.DestroyTiming and def.DestroyTiming[1] and def.DestroyTiming[1][2] then
        duration = math.floor(def.DestroyTiming[1][2])
    end

    unit.buffs[buffId] = {
        expireAt = now + duration,
        attr = self:ParseBuffEffect(buffId),
    }

    local attrs = self:RecalcAttr(unit)

    local set = self:GetNeighborSet(unit.gx, unit.gz)
    local receivers = {}
    for id in pairs(set) do
        receivers[#receivers + 1] = id
    end

    return {
        uid = uid,
        buffId = buffId,
        duration = duration,
        attr = attrs,
        receivers = receivers,
    }
end

function Scene:UpdateBuffs(now, events)
    for _, unit in pairs(self.units) do
        for buffId, buff in pairs(unit.buffs or {}) do
            if now >= buff.expireAt then
                unit.buffs[buffId] = nil
                local attrs = self:RecalcAttr(unit)

                local set = self:GetNeighborSet(unit.gx, unit.gz)
                local receivers = {}
                for id in pairs(set) do
                    receivers[#receivers + 1] = id
                end

                events[#events + 1] = {
                    kind = "buff", uid = unit.uid, buffId = buffId,
                    duration = 0, receivers = receivers,
                }
                events[#events + 1] = {
                    kind = "attr", uid = unit.uid,
                    atk = attrs.atk, def = attrs.def,
                    maxHp = attrs.maxHp, hp = attrs.hp,
                    maxSp = attrs.maxSp, sp = attrs.sp,
                    receivers = receivers,
                }
            end
        end
    end
end

function Scene:ApplyBaseAttr(unit, attrs)
    return unit:GetComponent(AttributeComponent):SetBase(attrs)
end

function Scene:SetAttr(uid, attrs, now)
    local unit = self.units[uid]
    if not unit or not unit:GetComponent(AttributeComponent) then
        return nil
    end

    local result = self:ApplyBaseAttr(unit, attrs)

    local set = self:GetNeighborSet(unit.gx, unit.gz)
    local receivers = {}
    for id in pairs(set) do
        receivers[#receivers + 1] = id
    end

    return {
        uid = uid,
        atk = result.atk,
        def = result.def,
        maxHp = result.maxHp,
        hp = result.hp,
        receivers = receivers,
    }
end

function Scene:ParseBuffEffect(buffId)
    local def = ConfigRepository.Get("tbbufftable")[buffId]
    if not def then
        return {}
    end

    local attr = {}

    for _, effectId in ipairs(def.EffectGroup or {}) do
        local effect = ConfigRepository.Get("tbbuffeffecttable")[effectId]
        if effect and effect.EffectType == 2 then
            for pair in string.gmatch(effect.EffectParam or "", "([^|]+)") do
                local k, v = string.match(pair, "^(%d+)=(%-?%d+)$")
                k, v = tonumber(k), tonumber(v)
                if k and v then
                    local field = ATTR_MAP[k]
                    if field then
                        attr[field] = (attr[field] or 0) + v
                    end
                end
            end
        end
    end

    return attr
end

function Scene:RecalcAttr(unit)
    return unit:GetComponent(AttributeComponent):Recalculate()
end

-- 主目标固定在首位，范围技能额外选取半径内存活的敌对战斗单位。
function Scene:SelectSkillTargets(uid, skill, effect, primaryUid)
    local caster = self.units[uid]
    local primary = self.units[primaryUid]
    if not caster or not primary or not (primary:IsMonster() or primary:IsPlayer()) then
        return nil
    end

    local skills = caster:GetComponent(SkillComponent)
    if not skills or not skills:CanSelectPrimary(skill, primary) then
        return nil
    end

    local targets = {primary}

    if skill.IsAoe then
        local radius = effect.EffectRange and effect.EffectRange[1] or 0
        if radius <= 0 then
            radius = 3.0
        end

        for id, u in pairs(self.units) do
            if id ~= uid and id ~= primaryUid and not u.dead and IsEnemy(caster, u) then
                local d = math.sqrt((u.x - primary.x)^2 + (u.z - primary.z)^2)
                if d <= radius then
                    table.insert(targets, u)
                end
            end
        end
    end
    return targets
end

function Scene:IsBlocked(x, z)
    local g = self.grid
    if x < g.minX or x > g.maxX or z < g.minZ or z > g.maxZ then
        return true
    end

    for _, r in ipairs(g.blocked or {}) do
        if x >= r.x1 and x <= r.x2 and z >= r.z1 and z <= r.z2 then
            return true
        end
    end

    return false
end

local function toCell(scene, x, z)
    local g = scene.grid
    return math.floor((x - g.minX) / g.cell),
           math.floor((z - g.minZ) / g.cell)
end

local function toWorld(scene, gx, gz)
    local g = scene.grid
    return g.minX + (gx + 0.5) * g.cell,
           g.minZ + (gz + 0.5) * g.cell
end

local DIRS = {
    {1, 0}, {-1, 0}, {0, 1}, {0, -1},
}

-- 四邻格 A*，返回从下一步到目标的路点；超出搜索预算或不可达时返回 nil。
function Scene:FindPath(sx, sz, tx, tz, maxSteps)
    maxSteps = maxSteps or 4000

    local startX, startZ = toCell(self, sx, sz)
    local goalX, goalZ = toCell(self, tx, tz)

    local function key(x,z) return x .. "," .. z end

    if self:IsBlocked(sx, sz) or self:IsBlocked(tx, tz)
        or not self:GetHeight(sx, sz) or not self:GetHeight(tx, tz) then
        return nil
    end
    if startX == goalX and startZ == goalZ then
        if self:CanWalk(sx, sz, tx, tz) then
            return {{x = tx, z = tz}}
        end
        return nil
    end

    local start = {
        x = startX,
        z = startZ,
        g = 0,
        wx = sx, wz = sz,
        f = math.abs(goalX - startX) + math.abs(goalZ - startZ),
        parent = nil,
    }

    local open = {start}
    local openMap = {[key(startX, startZ)] = start}
    local closed = {}

    local steps = 0
    while #open > 0 and steps < maxSteps do
        steps = steps + 1

        local bestIdx = 1
        for i = 2, #open do
            if open[i].f < open[bestIdx].f then
                bestIdx = i
            end
        end

        local cur = table.remove(open, bestIdx)
        openMap[key(cur.x, cur.z)] = nil

        if cur.x == goalX and cur.z == goalZ then
            local path = {}
            local node = cur
            while node.parent do
                table.insert(path, {x = node.wx, z = node.wz})
                node = node.parent
            end
            local result = {}
            for i = #path, 1, -1 do
                table.insert(result, path[i])
            end
            return result
        end

        closed[key(cur.x, cur.z)] = true

        for _, d in ipairs(DIRS) do
            local nx, nz = cur.x + d[1], cur.z + d[2]
            local k = key(nx, nz)
            if not closed[k] then
                local wx, wz = toWorld(self, nx, nz)
                if nx == goalX and nz == goalZ then
                    wx, wz = tx, tz
                end
                if self:CanWalk(cur.wx, cur.wz, wx, wz) then
                    local g = cur.g + 1
                    local h = math.abs(goalX - nx) + math.abs(goalZ - nz)
                    local f = g + h
                    local node = openMap[k]
                    if not node then
                        node = {x = nx, z = nz, wx = wx, wz = wz, g = g, f = f, parent = cur}
                        table.insert(open, node)
                        openMap[k] = node
                    elseif g < node.g then
                        node.g = g
                        node.f = f
                        node.parent = cur
                    end
                end
            end
        end
    end
    return nil
end

-- 返回线段在单轴投影内的参数区间，用于判定整段是否与障碍矩形相交。
local function axisInterval(start, delta, low, high)
    if delta == 0 then
        if start >= low and start <= high then
            return 0, 1
        end
        return 1, 0
    end
    local a, b = (low - start) / delta, (high - start) / delta
    return math.min(a, b), math.max(a, b)
end

-- 检查线段经过的障碍和相邻格高差，成功时返回终点地面高度。
function Scene:CanWalk(fromX, fromZ, toX, toZ)
    local height, targetHeight = self:GetHeight(fromX, fromZ), self:GetHeight(toX, toZ)
    if not height or not targetHeight then
        return false
    end
    local dx, dz = toX - fromX, toZ - fromZ
    local grid = self.grid
    for _, r in ipairs(grid.blocked or {}) do
        local xEnter, xExit = axisInterval(fromX, dx, r.x1, r.x2)
        local zEnter, zExit = axisInterval(fromZ, dz, r.z1, r.z2)
        if math.max(0, xEnter, zEnter) <= math.min(1, xExit, zExit) then
            return false
        end
    end
    if grid.cells then
        local gx, gz = toCell(self, fromX, fromZ)
        local endX, endZ = toCell(self, toX, toZ)
        local stepX, stepZ = dx > 0 and 1 or -1, dz > 0 and 1 or -1
        while gx ~= endX or gz ~= endZ do
            -- 比较线段到下一条 X/Z 格线的距离比例；同时到达表示穿过格点。
            local nextX = gx == endX and math.huge or
                (grid.minX + (gx + (dx > 0 and 1 or 0)) * grid.cell - fromX) / dx
            local nextZ = gz == endZ and math.huge or
                (grid.minZ + (gz + (dz > 0 and 1 or 0)) * grid.cell - fromZ) / dz
            if nextX <= nextZ then gx = gx + stepX end
            if nextZ <= nextX then gz = gz + stepZ end
            local wx, wz = toWorld(self, gx, gz)
            local nextHeight = self:GetHeight(wx, wz)
            if not nextHeight or math.abs(nextHeight - height) > HEIGHT_LEGAL_DIFF + 1e-9 then
                return false
            end
            height = nextHeight
        end
    end
    return true, targetHeight
end

function Scene:LoadHeightLayers(baseName)
    local dir = "./../config/Asserts/Resources/MlyDatas/"
    for layer = 0, 3 do
        local path = dir .. baseName .. "-" .. layer .. ".mly"
        local g = MapLayerParser.Parse(path, layer)
        if g then
            self.heightLayers[layer] = g
        end
    end
end

-- 从厘米高度格取地面高度。空洞和格网外的位置不可行走。
local function sampleHeight(g, x, z)
    local gx = math.floor((x - g.minX) / g.cell)
    local gz = math.floor((z - g.minZ) / g.cell)
    if gx < 0 or gx >= g.width or gz < 0 or gz >= g.height then
        return nil
    end
    local v = g.cells[gz * g.width + gx + 1]
    if v and v ~= -100 and v ~= 0 then
        return v / 100.0
    end
end

function Scene:GetHeights(x, z)
    local result = {}
    for layer, g in pairs(self.heightLayers or {}) do
        result[layer] = sampleHeight(g, x, z)
    end
    return result
end

-- 有分层地形时沿用层选择；旧地图使用自身高度格或出生点的平面高度。
function Scene:GetHeight(x, z, preferY)
    if not next(self.heightLayers) then
        local g = self.grid
        if not g or x < g.minX or x > g.maxX or z < g.minZ or z > g.maxZ then
            return nil
        end
        if g.cells then
            return sampleHeight(g, x, z)
        end
        return self.startPos[2] or 0
    end
    local hs = self:GetHeights(x, z)
    if not hs[0] then
        return nil
    end

    preferY = preferY or hs[0]
    local best, bestDiff
    for _, h in pairs(hs) do
        local d = math.abs(h - preferY)
        if not bestDiff or d < bestDiff then
            best, bestDiff = h, d
        end
    end
    return best
end

return Scene
