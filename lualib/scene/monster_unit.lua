local Class = require "common.class"
local SceneUnit = require "scene.scene_unit"

local ATTACK_RANGE = 2.0
local ATTACK_CD = 1.0
local ATTACK_DAMAGE = 50

---@class MonsterUnit:SceneUnit
---@field entityId number
---@field speed number
---@field sight number
---@field aiType string
---@field targetUid number
---@field nextAttackAt number
---@field spawnX number
---@field spawnZ number
---@field state string
---@field hatred table<number, table>
---@field leashRange number
---@field skillIds table
local MonsterUnit = Class("MonsterUnit", SceneUnit)

function MonsterUnit:Ctor(entityId, x, z)
    SceneUnit.Ctor(self)

    self.entityId = entityId
    self.speed = 0
    self.sight = 0 -- 视野
    self.aiType = ""
    self.targetUid = nil
    self.nextAttackAt = 0
    self.spawnX, self.spawnZ = x, z
    self.state = "idle" -- idle / chase / attack / return
    self.hatred = {} -- uid -> {treat = number, at = now}
    self.leashRange = 15.0 -- 离出生点脱战距离
    self.skillIds = {}

    self.path = nil
    self.pathIndex = 1
    self.pathGoalX = nil
    self.pathGoalZ = nil
end

function MonsterUnit:Pack()
    local pack = SceneUnit.Pack(self)
    pack.unitType = 1
    pack.entityId = self.entityId
    return pack
end

function MonsterUnit:IsPlayer()
    return false
end

function MonsterUnit:IsMonster()
    return true
end

--- @param scene Scene
function MonsterUnit:UpdateAI(scene, now, events)
    local dt = 0.3
    local homeDist = math.sqrt((self.x - self.spawnX)^2 + (self.z - self.spawnZ)^2)

    -- 脱战
    if self.state == "return" then
        if homeDist <= 0.5 then
            self.hp = self.maxHp
            self.state = "idle"
            self.hatred = {}

            local set = scene:GetNeighborSet(self.gx, self.gz)
            local receivers = {}
            for id in pairs(set) do
                table.insert(receivers, id)
            end

            table.insert(events, {
                kinf = "hp",
                uid = self.uid,
                hp = self.hp,
                maxHp = self.maxHp,
                receivers = receivers,
            })
        else
            self:StepTo(scene, self.spawnX, self.spawnZ, dt, events)
        end
        return
    end

    local target = self:PickTarget(scene, now)
    if not target then
        self.state = homeDist > 0.5 and "return" or "idle"
        return
    end

    if homeDist > self.leashRange then
        self.hatred = {}
        self.state = "return"
        return
    end

    local dist = math.sqrt((target.x - self.x)^2 + (target.z - self.z)^2)

    if dist > self.sight * 1.5 then
        self.hatred = {}
        self.state = "return"
        return
    end

    if dist > ATTACK_RANGE then
        self.state = "chase"
        self:StepTo(scene, target.x, target.z, dt, events)
        return
    end

    self.state = "attack"
    
    if self:TryCastSkills(scene, target, now, events) then
        return
    end

    if now < self.nextAttackAt then
        return
    end

     self.nextAttackAt = now + ATTACK_CD
    target.hp = math.max(0, target.hp - ATTACK_DAMAGE)

    local dead = false
    if target.hp == 0 and not target.dead then
        target.dead = true
        dead = true
    end

    local set = scene:GetNeighborSet(target.gx, target.gz)
    local receivers = {}
    for id in pairs(set) do
        receivers[#receivers + 1] = id
    end

    table.insert(events, {
        kind = "hp",
        uid = target.uid,
        hp = target.hp,
        maxHp = target.maxHp,
        receivers = receivers,
    })
    if dead then
        table.insert(events, {
            kind = "dead",
            uid = target.uid,
            receivers = receivers,
        })
    end
end

function MonsterUnit:AddHatred(uid, threat, now)
    local h = self.hatred[uid]
    if not h then
        h = {treat = threat, at = now}
        self.hatred[uid] = h
    end

    h.threat = h.threat + threat
    h.at = now
end

-- 优先仇恨最高；没有仇恨再找视野内最近的玩家
---@param scene Scene
function MonsterUnit:PickTarget(scene, now)
    local best, bestThreat
    for uid, h in pairs(self.hatred) do
        local u = scene:GetUnit(uid)
        if not u or u.dead or now - h.at > 10 then
            self.hatred[uid] = nil
        elseif not bestThreat or h.threat > bestThreat then
            best, bestThreat = u, h.threat
        end
    end
    if best then
        return best
    end

    return scene:FindNearestPlayer(self)
end

---@param scene Scene
---@param x number
---@param z number
---@param dt number
---@param events table
function MonsterUnit:StepTo(scene, x, z, dt, events)
    local goalMoved = not self.pathGoalX
        or math.abs(x - self.pathGoalX) > 2
        or math.abs(z - self.pathGoalZ) > 2

    if not self.path or goalMoved or self.pathIndex > #self.path then
        self.path = scene:FindPath(self.x, self.z, x, z)
        self.pathIndex = 1
        self.pathGoalX, self.pathGoalZ = x, z
    end

    local node = self.path and self.path[self.pathIndex]
    if not node then
        -- 没有路径：直线兜底
        return self:StepDirect(scene, x, z, dt, events)
    end

    local dx, dz = node.x - self.x, node.z - self.z
    local dist = math.sqrt(dx * dx + dz * dz)

    if dist < 0.3 then
        self.pathIndex = self.pathIndex + 1
        return false
    end

    local step = math.min(self.speed * dt, dist)
    local nx = self.x + dx / dist * step
    local nz = self.z + dz / dist * step

    local result = scene:Move(self.uid, {
        common = 0, time = dt,
        dx = nx, dy = self.y, dz = nz,
    })
    if result and not result.forced then
        events[#events + 1] = { kind = "move", uid = self.uid, result = result }
    end
    return dist <= step
end

function MonsterUnit:TryCastSkills(scene, target, now, events)
    for _, entry in ipairs(self.skillIds or {}) do
        local skillId = entry[1]
        if not skillId then
            goto continue
        end

        local result = scene:CastSkill(self.uid, {
            skillId = skillId,
            targetUid = target.uid,
        }, now)

        if result and result.code == 0 then
            for _, hit in ipairs(result.hits or {}) do
                table.insert(events, {
                    kind = "hp",
                    uid = hit.uid,
                    hp = hit.hp,
                    maxHp = hit.maxHp,
                    receivers = hit.receivers,
                })
                if hit.dead then
                    table.insert(events, {
                        kind = "dead",
                        uid = hit.uid,
                        receivers = hit.deadReceivers,
                    })
                end
            end
            -- 技能附带的 Buff
            for _, buff in ipairs(result.buffs or {}) do
                events[#events + 1] = {
                    kind = "buff",
                    uid = buff.uid,
                    buffId = buff.buffId,
                    duration = buff.duration,
                    receivers = buff.receivers,
                }
            end
            return true
        end
        ::continue::
    end
    return false
end

return MonsterUnit