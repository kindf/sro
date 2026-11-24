-- 第 16 课。在项目根目录运行 lua tests/unit/test_skill_sp_charge.lua。
package.path = "./lualib/?.lua;" .. package.path

local ticks, handlers = 0, {}
local skynet = {now = function() return ticks end}
package.loaded.skynet = skynet
package.loaded["skynet.socket"] = {}
package.loaded["common.logger"] = {}
package.loaded["common.config_repository"] = {
    Get = function(name) return require("gamedata.generated." .. name) end,
}
package.loaded["protocol.protocol_helper"] = {
    RegisterPTCHandler = function(name, handler) handlers[name] = handler end,
    EncodePTCPacket = function(name, body) return {name = name, body = body} end,
}

local Scene = require "scene.scene"
local scenes = require("scene.scene_manager").GetInstance()
local commands = require("scene.scene_service_handler").CMD
local players = require("world.player.player_manager").GetInstance()
local loader = require "world.player.player_loader"
local SkillComponent = require "scene.skill_component"
require "world.client_handler"

-- 使用实际的场景命令；保留 world 组包前的施法结果以核对 hit 的施法号。
local sceneResult
function skynet.call(address, protocol, command, ...)
    assert(address == ".scene" and protocol == "lua")
    local result, reason = assert(commands[command], command)(...)
    if command == "cast_skill" then sceneResult = result end
    return true, result, reason
end

local arena = Scene.new({ID = 4, StartPos = {{0, 0, 0}}})
arena:LoadGrid(nil)
scenes.scenes[4] = arena
local function enter(fd)
    local role = loader.LoadPlayer(fd, tostring(fd))
    role.packets = {}
    function role:SendPackage(packet) table.insert(self.packets, packet) end
    players:AddPlayer(role.uid, role)
    handlers["Scene.ReqEnter"](role, {sceneId = 4})
    return role
end

local hero, observer = enter(1601), enter(1602)
local caster = assert(arena:GetUnit(hero.uid))
local skills = assert(caster:GetComponent(SkillComponent))
local a = assert(arena:AddMonster(1005, 1, 0))
local b = assert(arena:AddMonster(1005, 2, 0))
local both = {a, b}
assert(hero:LearnSkill(2) and hero:LearnSkill(610206))

-- 旁听每个目标开始结算伤害时的余额，能检出把扣费推迟到伤害循环之后的实现。
local spAtDamage = {}
local calculateDamage = arena.CalculateHitDamage
function arena:CalculateHitDamage(...)
    table.insert(spAtDamage, caster.sp)
    return calculateDamage(self, ...)
end

-- startingSp 为 nil 表示同一时刻立即重放，保留上一请求的余额和冷却。
local function cast(label, id, startingSp, expectedCode, expectedSp, expectedTargets)
    if startingSp ~= nil then
        ticks = ticks + 1000
        caster.sp = startingSp
    end
    local last, cooldown = skills.lastCast, caster.skillCooldown[id]
    local group = caster.skillGroupReadyAtMs[1]
    local hp = {[a.uid] = a.hp, [b.uid] = b.hp}
    hero.packets, observer.packets, spAtDamage, sceneResult = {}, {}, {}, nil
    handlers["Scene.ReqCastSkill"](hero, {skillId = id, targetUid = a.uid})
    local reply = assert(hero.packets[1], label .. " 缺少施法回复")
    assert(reply.name == "Scene.RespCastSkill" and sceneResult and sceneResult.code == reply.body.code, label)
    assert(reply.body.code == expectedCode, ("%s：应返回 %d，实际 %d"):format(label, expectedCode, reply.body.code))
    assert(caster.sp == expectedSp, ("%s：应剩 %d SP，实际 %d"):format(label, expectedSp, caster.sp))
    if expectedCode ~= 0 then
        assert(#spAtDamage == 0 and #reply.body.hits == 0 and #observer.packets == 0 and #hero.packets == 1, label)
        assert(not sceneResult.castId and skills.lastCast == last and caster.skillCooldown[id] == cooldown, label)
        assert(caster.skillGroupReadyAtMs[1] == group and a.hp == hp[a.uid] and b.hp == hp[b.uid], label)
        return
    end
    assert(skills.lastCast == sceneResult.cast and skills.lastCast.skillId == id, label)
    assert(not last or sceneResult.castId == last.castId + 1, label)
    assert(caster.skillCooldown[id] == ticks / 100, label)
    if id == 2 then assert(caster.skillGroupReadyAtMs[1] == ticks * 10 + 2000, label) end
    assert(#spAtDamage == #expectedTargets and #reply.body.hits == #expectedTargets, label)
    for _, balance in ipairs(spAtDamage) do assert(balance == expectedSp, label .. " 打击时余额错误") end
    local damage, updates = {}, {}
    for i, hit in ipairs(reply.body.hits) do
        assert(not damage[hit.uid] and hit.damage > 0 and hp[hit.uid] - hit.damage == hit.hp, label)
        assert(sceneResult.hits[i].castId == sceneResult.castId and arena:GetUnit(hit.uid).hp == hit.hp, label)
        damage[hit.uid] = hit.damage
    end
    for _, packet in ipairs(observer.packets) do
        if packet.name == "Scene.UnitHp" then
            local uid = packet.body.uid
            assert(damage[uid] and not updates[uid] and arena:GetUnit(uid).hp == packet.body.hp, label)
            updates[uid] = true
        end
    end
    for _, target in ipairs(expectedTargets) do assert(damage[target.uid] and updates[target.uid], label) end
    for _, target in ipairs(both) do assert(target.hp == hp[target.uid] - (damage[target.uid] or 0), label) end
end

cast("空装怒爆命中两怪", 2, 40, 0, 20, both)
local hat = 1070148
local slot = assert(hero:AddItem(hat, 1))[1].slot
handlers["Scene.ReqEquipItem"](hero, {slot = slot})
assert(hero.equipment[7] == hat)
cast("穿帽后 19 SP 仍未过准入", 2, 19, 8, 19)
cast("穿帽怒爆命中两怪只扣 16", 2, 20, 0, 4, both)
cast("组冷却内立即重放", 2, nil, 4, 4)

-- 专属 -50% 与装备 -20% 都作用于基础费用10，准入5，实际只扣3。
assert(hero:ApplyBuff(410218001))
cast("回旋之刃叠加两种百分比", 610206, 5, 0, 2, {a})
handlers["Scene.ReqUnequipItem"](hero, {equipSlot = 7})
assert(not hero.equipment[7])
cast("卸帽恢复怒爆原价", 2, 20, 0, 0, both)

-- 将魔力掌控者三件的属性 88=1000 从场景属性入口传入，只检验套装属性生效后的扣费。
assert(arena:SetAttr(caster.uid, {spCostFlat = 0, spCostRate = 1000}, ticks / 100))
cast("过了 20 点准入但付不起 22", 2, 20, 8, 20)
cast("实际费用少一点", 2, 21, 8, 21)
cast("实际费用刚好够", 2, 22, 0, 0, both)

-- 用隔离输入 +5 检验属性87，同时验证真正免费的 {0,0} 跳过资源写入。
assert(arena:SetAttr(caster.uid, {spCostFlat = 5, spCostRate = 0}, ticks / 100))
cast("固定费用刚好够", 2, 25, 0, 0, both)
cast("带固定加费时零 SP 普攻", 1, 0, 0, 0, {a})
print("OK skill SP charge")
