local Class = require "common.class"

---@class AttributeComponent
---@field baseAtk number
---@field baseDef number
---@field baseMaxSp number
---@field baseMaxHp number
---@field atk number
---@field def number
local AttributeComponent = Class("AttributeComponent")

function AttributeComponent:Ctor(owner, attack, defense)
    self.owner = owner
    self.baseAtk, self.baseDef = attack, defense
    self.baseMaxHp, self.baseMaxSp = owner.maxHp, owner.maxSp
    self.atk, self.def = attack, defense
end

-- 写入一段技能造成的 HP 变化，让监听器能立即读到本段结算后的血量
function AttributeComponent:ApplyHit(scene, firerUid, damage)
    local unit = self.owner
    local before = unit.hp
    unit.hp = math.max(0, before - damage)
    local delta = unit.hp - before
    if delta == 0 then
        return
    end

    scene.battleEvents:Dispatch({
        type = "kActionHpChange",
        entityUid = unit.uid,
        firerUid = firerUid,
        mercenaryUid = 0,
        hpChange = delta,
    })
end

function AttributeComponent:SetBase(attrs)
    self.baseAtk = attrs.atk or self.baseAtk
    self.baseDef = attrs.def or self.baseDef
    self.baseMaxHp = attrs.maxHp or self.baseMaxHp
    self.baseMaxSp = attrs.maxSp or self.baseMaxSp
    return self:Recalculate()
end

function AttributeComponent:Recalculate()
    local unit = self.owner
    local atk, def = self.baseAtk, self.baseDef
    local maxHp, maxSp = self.baseMaxHp, self.baseMaxSp
    for _, buff in pairs(unit.buffs) do
        local bonus = buff.attr or {}
        atk = atk + (bonus.atk or 0)
        def = def + (bonus.def or 0)
        maxHp = maxHp + (bonus.maxHp or 0)
        maxSp = maxSp + (bonus.maxSp or 0)
    end

    self.atk, self.def = atk, def
    unit.maxHp, unit.maxSp = maxHp, maxSp
    unit.hp = math.min(unit.hp, maxHp)
    unit.sp = math.min(unit.sp, maxSp)
    return {atk = atk, def = def, maxHp = maxHp, hp = unit.hp, maxSp = maxSp, sp = unit.sp}
end

return AttributeComponent