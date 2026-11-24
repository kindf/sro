local ConfigRepository = require "common.config_repository"
local f32 = require "common.float32"

local SkillRange = {}

local ZERO_EPSILON = f32(1e-6)
local BASE_TOLERANCE = f32(0.1)
-- 打击范围允许垂直高差，单位为米
local DAMAGE_DISTANCE_HEIGHT = 6.0
local ROLE_INTERVAL = f32(100/1000)
local AI_INTERVAL = f32(299/1000)

-- 取 float 坐标差，保留点积和开方各自的舍入点。
local function horizontalDistance(a, b)
    local dx = f32(f32(a.x) - f32(b.x))
    local dz = f32(f32(a.z) - f32(b.z))
    if math.abs(dx) < ZERO_EPSILON and math.abs(dz) < ZERO_EPSILON then
        return 0
    end
    local squared = f32(f32(dx * dx) + f32(dz * dz))
    return f32(math.sqrt(squared))
end

-- 比较打击中心和单位的场景高度；等于上下限时仍在范围内。
function SkillRange.WithinDamageHeight(center, target)
    local dy = f32(f32(center.y) - f32(target.y))
    return math.abs(dy) <= DAMAGE_DISTANCE_HEIGHT
end

function SkillRange.MonsterRadius(presentId)
    local present = ConfigRepository.Get("tbpresenttable")[presentId]
    local boxes = present and present.HugeMonsterColliders
    if not boxes or #boxes ~= 1 then
        return 0
    end
    local box = boxes[1]
    if #box ~= 4 or box[1] ~= 0 or box[2] ~= 0 then
        return 0
    end
    return box[3]
end

-- 施法容错距离
local function targetTolerance(target)
    local speedAttr = math.modf(f32(f32(target.speed) * 100))
    local speed = f32(speedAttr / 100)
    local isPlayer = target:IsPlayer()
    local interval = isPlayer and ROLE_INTERVAL or AI_INTERVAL
    local allowance = f32(f32(speed * interval) * 2)
    if not isPlayer then
        allowance = f32(allowance + target.singingTargetRadius)
    end
    return f32(BASE_TOLERANCE + allowance)
end

local function inRange(distance, low, far, tolerance)
    return distance >= f32(low - tolerance) and distance <= f32(far + tolerance)
end

function SkillRange.Contains(caster, requestPoint, lockedTarget, effect)
    local low = f32(effect.LowRange or 0)
    local far = f32(effect.FarRange or 2.0)
    if lockedTarget then
        local distance = horizontalDistance(caster, lockedTarget)
        if not inRange(distance, low, far, targetTolerance(lockedTarget)) then
            return false
        end
    end

    local key = caster:IsMonster() and "MonsterTolerateRange" or "PlayerTolerateRange"
    local row = ConfigRepository.Get("tbglobaltable")[key]
    local tolerance = assert(row and tonumber(row.Value), key)
    return inRange(horizontalDistance(caster, requestPoint), low, far, f32(tolerance))
end

return SkillRange
