local Class = require "common.class"
local SceneUnit = require "scene.scene_unit"

local ATTACK_RANGE = 2.0
local ATTACK_CD = 1.0
local ATTACK_DAMAGE = 50

---@class MonsterUnit:SceneUnit
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
    local target = scene:FindNearestPlayer(self)
    if not target then
        return
    end

    local dist = math.sqrt((target.x - self.x)^2 + (target.z - self.z)^2)
    if dist < ATTACK_RANGE then
        local dt = 0.3
        local step = math.min(self.speed * dt, dist - 1.0)
        local nx = self.x + (target.x - self.x) / dist * step
        local nz = self.z + (target.z - self.z) / dist * step

        local result = scene:Move(self.uid, {
            common = 0,
            time = dt,
            dx = nx,
            dy = self.y,
            dz = nz,
        })

        if result and not result.forced then
            table.insert(events, {
                kind = "move",
                uid = self.uid,
                result = result,
            })
        end
    elseif now >= self.nextAttackAt then
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
            table.insert(receivers, id)
        end

        table.insert(events, {
            kind = "hp",
            uid = target.uid,
            hp = target.hp,
            maxHp = target.maxHp,
            dead = dead,
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
end

return MonsterUnit