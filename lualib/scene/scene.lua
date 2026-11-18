local Class = require "common.class"
local SceneUnit = require "scene.scene_unit"
local Logger = require "common.logger"
local MonsterUnit = require "lualib.scene.monster_unit"
local ConfigRepository = require "common.config_repository"
local DropUnit = require("lualib.scene.drop_unit")

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

local ATTR_MAP = {
    [51] = "atk",
    [53] = "def",
    [312] = "atk",
    [186] = "def",
}

local function IsEnemy(a, b)
    return a:IsMonster() ~= b:IsMonster()
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
local Scene = Class("Scene")

function Scene:Ctor(cfg)
    self.sceneId = cfg.ID
    self.units = {}
    self.grids = {}

    self.startPos = cfg.StartPos and cfg.StartPos[1] or {0, 0, 0}
    self.startFace = cfg.StartFace or 0

    local size = cfg.MapSize and cfg.MapSize[1] or 0
    local offset = cfg.MapOffset and cfg.MapOffset[1] or {0, 0}

    if size > 0 then
        self.minX, self.maxX = offset[1], offset[1] + size
        self.minZ, self.maxZ = offset[2], offset[2] + size
    else
        self.minX, self.maxX = -DEFAULT_MIN_X, DEFAULT_MAX_X
        self.minZ, self.maxZ = DEFAULT_MIN_Z, DEFAULT_MAX_Z
    end

    self.spawns = {}
    self.monsterSeq = 0
    self.dropSeq = 0
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

function Scene:Enter(uid, x, y, z)
    if not x then
        x, y, z = self.startPos[1], self.startPos[2], self.startPos[3]
    end
    local unit = SceneUnit.new()
    unit.uid = uid
    unit.x = x
    unit.y = y
    unit.z = z
    unit.face = self.startFace or 0
    unit.lastMoveAt = os.time()
    unit.token = TOKEN_MAX
    unit.dead = false
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

    local now = os.time()
    local dt = now - unit.lastMoveAt
    if dt < 0 then dt = 0 end
    if dt > MAX_DT then dt = MAX_DT end

    unit.token = math.min(TOKEN_MAX, unit.token + dt * TOKEN_REGEN)
    local dist = math.sqrt((dx - unit.x)^2 + (dz - unit.z)^2)
    local cost = dist / (MAX_SPEED * SPEED_TOLERANCE)
    if cost > unit.token then
        unit.token = 0
        unit.lastMoveAt = now
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
    unit.x, unit.y, unit.z = dx, dy, dz
    unit.lastMoveAt = now
    unit.token = unit.token - cost
    unit.face = common & 0xFFFF
    unit.moving = ((common >> 30) & 1) == 1
    self:RemoveFromGrid(unit)
    self:AddToGrid(unit)

    return {
        dx = dx,
        dy = dy,
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

local function MergeReward(a, b)
    if not b then return a end
    if not a then
        return {
            baseExp = b.baseExp,
            jobExp = b.jobExp,
            totalBaseExp = b.totalBaseExp,
            totalJobExp = b.totalJobExp,
            level = b.level,
            drops = b.drops or {},
            dropReceivers = b.dropReceivers or {},
        }
    end

    a.baseExp = a.baseExp + b.baseExp
    a.jobExp = a.jobExp + b.jobExp
    a.totalBaseExp = b.totalBaseExp
    a.totalJobExp = b.totalJobExp
    a.level = b.level

    for _, d in ipairs(b.drops or {}) do
        a.drops[#a.drops + 1] = d
    end
    for _, uid in ipairs(b.dropReceivers or {}) do
        a.dropReceivers[uid] = true
    end
    return a
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

    if not unit then
        failed.code = SKILL_NOT_SELF
        return failed
    end

    local skill = ConfigRepository.Get("tbskilltable")[req.skillId]
    local effect = skill and skill.EffectIDs and skill.EffectIDs[1]
    effect = effect and ConfigRepository.Get("tbskilleffecttable")[effect]
    if not effect then
        failed.code = SKILL_INVALID
        return failed
    end

    local targets = self:SelectSkillTargets(uid, skill, effect, req.targetUid)
    if not targets then
        failed.code = SKILL_NO_TARGET
        return failed
    end

    local primary = targets[1]
    local dist = math.sqrt((primary.x - unit.x)^2 + (primary.z - unit.z)^2)
    if dist > (effect.FarRange or 2.0) then
        failed.code = SKILL_OUT_RANGE
        return failed
    end

    local cooldown = effect.PVECoolTime or 0
    local last = unit.skillCooldown[req.skillId] or 0
    if now - last < cooldown then
        failed.code = SKILL_COOLDOWNING
        return failed
    end

    -- SP 消耗
    local costType = effect.SkillCost and effect.SkillCost[1]
    local costValue = effect.SkillCost and effect.SkillCost[2] or 0
    if costType == 7 then
        if unit.sp < costValue then
            failed.code = SKILL_NO_COST
            return failed
        end
        unit.sp = unit.sp - costValue
    end

    local ratio = (effect.PVEDamageRadio and effect.PVEDamageRadio[1] or 10000) / 10000
    local static = effect.PVEStaticDam and effect.PVEStaticDam[1] or 0

    local hits = {}
    local deadReceivers = {}
    local rewardTotal = nil

    for _, target in ipairs(targets) do
        local perHit = math.floor(unit.atk * ratio + static - (target.def or 0))
        if ratio > 0 and perHit < 1 then perHit = 1 end
        if perHit < 0 then perHit = 0 end

        local totalDamage = 0
        local hitCount = effect.AttackCount and effect.AttackCount[1] or 1

        for i = 1, hitCount do
            if target.hp <= 0 then break end
            target.hp = math.max(0, target.hp - perHit)
            totalDamage = totalDamage + perHit
        end

        if target:IsMonster() then
            target:AddHatred(uid, totalDamage, now)
        end

        local dead = false
        if target.hp <= 0 and not target.dead then
            target.dead = true
            dead = true
        end

        local set = self:GetNeighborSet(target.gx, target.gz)
        set[uid] = nil
        local receivers = {}
        for id in pairs(set) do
            receivers[#receivers + 1] = id
        end

        hits[#hits + 1] = {
            uid = target.uid,
            damage = totalDamage,
            hp = target.hp,
            maxHp = target.maxHp,
            receivers = receivers,
            dead = dead,
            deadReceivers = dead and receivers or {},
        }

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

    return {
        code = SKILL_OK,
        targetUid = primary.uid,
        damage = hits[1] and hits[1].damage or 0,
        targetHp = primary.hp,
        maxHp = primary.maxHp,
        hits = hits,
        dead = hits[1] and hits[1].dead or false,
        deadReceivers = deadReceivers,
        reward = rewardTotal,
        buffs = buffs,
    }
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

    -- Award：awardId -> pack -> item
    for _, awardId in ipairs(cfg.Award or {}) do
        local items = self:RollAward(awardId)
        for _, item in ipairs(items) do
            local drop = self:DropItem(item.itemId, item.count, monster.x, monster.z)
            reward.drops[#reward.drops + 1] = drop:Pack()
        end
    end

    -- DropDoodad：直接 {itemId, count}
    for _, d in ipairs(cfg.DropDoodad or {}) do
        local drop = self:DropItem(d[1], d[2] or 1, monster.x, monster.z)
        reward.drops[#reward.drops + 1] = drop:Pack()
    end

    local set = self:GetNeighborSet(monster.gx, monster.gz)
    local receivers = {}
    for id in pairs(set) do
        receivers[#receivers + 1] = id
    end
    reward.dropReceivers = receivers

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
    unit.uid = MONSTER_UID_BASE + self.monsterSeq
    unit.hp = cfg.BaseHP
    unit.maxHp = cfg.BaseHP
    unit.speed = cfg.MoveSpeed
    unit.sight = cfg.Sight
    unit.aiType = cfg.AI[1]
    unit.atk = cfg.BaseATK > 0 and cfg.BaseATK or 10

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

function Scene:Pickup(uid, targetUid)
    local player = self.units[uid]
    local drop = self.units[targetUid]

    if not player or not drop or not drop:IsDrop() then
        return {code = 1} -- 不存在
    end

    local dist = math.sqrt((player.x - drop.x)^2 + (player.z - drop.z)^2)
    if dist > 2.0 then
        return {code = 2} -- 太远
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
    if not unit or not def then
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
                    receivers = receivers,
                }
            end
        end
    end
end

function Scene:SetAttr(uid, attrs, now)
    local unit = self.units[uid]
    if not unit then
        return nil
    end
    unit.baseAtk = attrs.atk or unit.baseAtk
    unit.baseDef = attrs.def or unit.baseDef
    unit.baseMaxHp = attrs.maxHp or unit.baseMaxHp
    unit.baseMaxSp = attrs.maxSp or unit.baseMaxSp

    local result = self:RecalcAttr(unit)

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
    local atk = unit.baseAtk
    local def = unit.baseDef
    local maxHp = unit.baseMaxHp
    local maxSp = unit.baseMaxSp

    for _, buff in pairs(unit.buffs or {}) do
        for field, value in pairs(buff.attr or {}) do
            if field == "atk" then
                atk = atk + value
            elseif field == "def" then
                def = def + value
            elseif field == "maxHp" then
                maxHp = maxHp + value
            elseif field == "maxSp" then
                maxSp = maxSp + value
            end
        end
    end

    unit.atk, unit.def = atk, def
    unit.maxHp, unit.maxSp = maxHp, maxSp
    unit.hp = math.min(unit.hp, unit.maxHp)
    unit.sp = math.min(unit.sp, unit.maxSp)

    return { atk = atk, def = def, maxHp = maxHp, maxSp = maxSp,
             hp = unit.hp, sp = unit.sp }
end

function Scene:SelectSkillTargets(uid, skill, effect, primaryUid)
    local caster = self.units[uid]
    local primary = self.units[primaryUid]
    if not caster or not primary or primary.dead then
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
end

return Scene